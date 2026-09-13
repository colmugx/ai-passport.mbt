///|
/// midi -> fixed-point phase increment for one cycle of [0, 2^31) at
/// SAMPLE_RATE: `increment = f * 2^31 / 16000`, where
/// `f = 440 * 2^((midi - 69) / 12)` is the equal-tempered frequency.
///
/// Floating point (Double) appears ONLY here, at module initialization, to
/// precompute this 128-entry table — the documented exception to the
/// integer-only hot path (docs/MUSIC.md fixed-point engine target). The
/// per-semitone chain below multiplies/divides by 2^(1/12) from the A4=440
/// anchor instead of calling a math library, and every result is rounded to
/// the nearest integer below 2^31 (midi 127 tops out at ~1.683e9), so the
/// per-sample path can stay pure integer. Built once per process;
/// `Synth::trigger` only reads it.
let increment_table : FixedArray[Int] = build_increment_table()

///|
/// Builds `increment_table` (see its docs for the Float-only rationale).
fn build_increment_table() -> FixedArray[Int] {
  let semitone : Double = 1.0594630943592953 // 2^(1/12)
  let scale : Double = 2147483648.0 / Double::from_int(SAMPLE_RATE)
  let freqs : FixedArray[Double] = FixedArray::make(128, 0.0)
  freqs[69] = 440.0
  let mut up = 440.0
  for midi in 70..<128 {
    up = up * semitone
    freqs[midi] = up
  }
  let mut down = 440.0
  for midi in 0..<69 {
    down = down / semitone
    freqs[68 - midi] = down
  }
  FixedArray::makei(128, midi => (freqs[midi] * scale + 0.5).to_int())
}

///|
/// Four monophonic synth voices (AGENTS.md rule 7) rendering the
/// docs/MUSIC.md engine target: 16000 Hz signed PCM16 mono, fixed-point
/// phase accumulator, allocation-free hot path.
///
/// DSP contract:
///
/// - Per-sample hot path (`render`) is pure integer and allocates nothing.
///   Floating point exists only in `increment_table` at module init
///   (documented there).
/// - Each voice runs a fixed-point phase accumulator over [0, 2^31) with an
///   explicit wrap after every addition — Int overflow is never relied
///   upon.
/// - Envelope: 16-bit fixed-point amplitude fraction (0..65536 =
///   0.0..1.0) with a preset per waveform (documented constants on
///   `envelope_preset`; musical roles per docs/MUSIC.md — Pulse12 short
///   celesta decay, Pulse50/Triangle slower strings/bass, Pulse25 lyrical
///   woodwind, Noise fast). Exhausting `gate_samples` enters release
///   automatically.
/// - Vibrato: light ~5 Hz triangle-LFO pitch modulation (~13 cents peak) on
///   Pulse25 only.
/// - Noise: 16-bit LFSR advanced once per sample from a fixed seed —
///   deterministic, so identical trigger+render sequences give identical
///   buffers.
/// - Per-voice peak is 12000: a four-voice mix stays inside PCM16 unless
///   loud presets stack, in which case `render` clamps into
///   [-32768, 32767] — the documented behavior.
///
/// # Example
/// ```mbt check
/// test {
///   let synth = Synth::new()
///   let pitch = @music.Pitch::from_midi(midi=69).unwrap()
///   synth.trigger(
///     voice=0,
///     on={ track: 0, pitch, eighths: 2, waveform: @music.Pulse12, },
///     gate_samples=256,
///   )
///   let out : FixedArray[Int] = FixedArray::make(256, 0)
///   synth.render(out~)
///   // The celesta pluck is audible one 256-frame chunk in.
///   inspect(out[255] != 0, content="true")
/// }
/// ```
pub struct Synth {
  priv voices : FixedArray[Voice]
}

///|
/// Creates a synth whose four voices are all idle: rendering it produces
/// silence until a voice is triggered.
///
/// # Example
/// ```mbt check
/// test {
///   let synth = Synth::new()
///   let out : FixedArray[Int] = FixedArray::make(8, 7)
///   synth.render(out~)
///   inspect(out[0], content="0")
///   inspect(out[7], content="0")
/// }
/// ```
pub fn Synth::new() -> Synth {
  { voices: FixedArray::makei(VOICES, _ => Voice::idle()), }
}

///|
/// Starts (or retriggers) one voice. `voice` must be in `0..<VOICES` and
/// `gate_samples` must be positive — anything else aborts as a programmer
/// error. Retriggering an active voice restarts its phase and envelope from
/// the top, so repeated triggers on one voice stay deterministic.
///
/// `on` is a sequencer note-start event; its midi pitch selects the
/// precomputed phase increment (out-of-range midi is clamped into the table
/// defensively — `@music.Pitch` normally already enforces 0..=127), and its
/// waveform selects the documented envelope preset. The voice then sounds
/// for `gate_samples` rendered samples before its release stage runs
/// automatically.
///
/// # Example
/// ```mbt check
/// test {
///   let synth = Synth::new()
///   let pitch = @music.Pitch::from_midi(midi=69).unwrap()
///   synth.trigger(
///     voice=0,
///     on={ track: 0, pitch, eighths: 2, waveform: @music.Pulse50, },
///     gate_samples=2000,
///   )
///   let out : FixedArray[Int] = FixedArray::make(4, 0)
///   synth.render(out~)
///   // The strings swell gradually: the first sample (attack step 64 of
///   // 65536) is only faintly audible.
///   inspect(out[0], content="11")
/// }
/// ```
pub fn Synth::trigger(
  self : Synth,
  voice~ : Int,
  on~ : @music.NoteOn,
  gate_samples~ : Int,
) -> Unit {
  if voice < 0 || voice >= VOICES {
    abort("Synth::trigger: voice must be in 0..\{VOICES - 1}, got \{voice}")
  }
  if gate_samples <= 0 {
    abort("Synth::trigger: gate_samples must be > 0, got \{gate_samples}")
  }
  let v = self.voices[voice]
  let midi = on.pitch.midi
  let clamped = if midi < 0 { 0 } else if midi > 127 { 127 } else { midi }
  v.active = true
  v.waveform = on.waveform
  v.preset = envelope_preset(on.waveform)
  // A retrigger restarts the phase accumulator, vibrato LFO, noise LFSR and
  // envelope so the voice always sounds identical for identical notes.
  v.phase = 0
  v.inc = increment_table[clamped]
  v.lfo_phase = 0
  v.lfsr = LFSR_SEED
  v.env = 0
  v.state = Attack
  v.gate = gate_samples
}

///|
/// Releases one voice early: it fades through its preset release stage
/// instead of waiting for `gate_samples` to run out. An idle voice is a
/// no-op. `voice` must be in `0..<VOICES` — anything else aborts as a
/// programmer error. Releasing before the first rendered sample silences
/// the voice immediately (the envelope has not risen yet).
///
/// # Example
/// ```mbt check
/// test {
///   let synth = Synth::new()
///   let pitch = @music.Pitch::from_midi(midi=69).unwrap()
///   synth.trigger(
///     voice=0,
///     on={ track: 0, pitch, eighths: 2, waveform: @music.Pulse50, },
///     gate_samples=8000,
///   )
///   synth.release(voice=0)
///   let out : FixedArray[Int] = FixedArray::make(256, 0)
///   synth.render(out~)
///   let mut nonzero = 0
///   for i in 0..<256 {
///     if out[i] != 0 {
///       nonzero += 1
///     }
///   }
///   inspect(nonzero, content="0")
/// }
/// ```
pub fn Synth::release(self : Synth, voice~ : Int) -> Unit {
  if voice < 0 || voice >= VOICES {
    abort("Synth::release: voice must be in 0..\{VOICES - 1}, got \{voice}")
  }
  let v = self.voices[voice]
  if v.active && !(v.state is Release) {
    v.state = Release
  }
}

///|
/// Mixes every active voice into `out`, advancing all per-voice state by
/// exactly `out.length()` samples, then clamps each mixed sample into
/// [-32768, 32767]. Any chunk length is allowed (256 frames is the typical
/// docs/MUSIC.md chunk); length 0 is a no-op. An idle synth renders silence
/// (all zeros). The hot path only writes into `out` — no allocation per
/// sample or per call.
///
/// Rendering in consecutive slices produces exactly the same samples as one
/// big render, which keeps `@music.TickClock`-driven chunked playback
/// deterministic.
///
/// # Example
/// ```mbt check
/// test {
///   let synth = Synth::new()
///   let out : FixedArray[Int] = FixedArray::make(3, 5)
///   synth.render(out~) // idle: silence, out.length() samples written
///   inspect(out[0], content="0")
///   inspect(out[1], content="0")
///   inspect(out[2], content="0")
/// }
/// ```
pub fn Synth::render(self : Synth, out~ : FixedArray[Int]) -> Unit {
  let n = out.length()
  if n == 0 {
    return
  }
  for i in 0..<n {
    let mut total = 0
    for k in 0..<VOICES {
      let v = self.voices[k]
      if v.active {
        total += v.next_sample()
      }
    }
    out[i] = if total > PCM16_MAX {
      PCM16_MAX
    } else if total < PCM16_MIN {
      PCM16_MIN
    } else {
      total
    }
  }
}
