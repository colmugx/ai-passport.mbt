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
/// - Envelope and volume come from the triggered `@music.Instrument` (never
///   from the waveform): the instrument's millisecond ADSR is converted
///   once at trigger time into per-sample integer steps of the 16-bit
///   fixed-point amplitude fraction (0..65536 = 0.0..1.0), and `volume`
///   (0..=100, clamped) scales the voice peak. Exhausting `gate_samples`
///   enters release automatically.
/// - Vibrato: light triangle-LFO pitch modulation applied only when the
///   instrument carries a `Vibrato` — rate from `rate_millihz`, depth from
///   `depth_cents` (linear approximation `depth/1731` of the phase
///   increment).
/// - Noise: 16-bit LFSR advanced once per sample from a fixed seed —
///   deterministic, so identical trigger+render sequences give identical
///   buffers.
/// - Per-voice peak is 12000 at volume 100: a four-voice mix stays inside
///   PCM16 unless loud instruments stack, in which case `render` clamps
///   into [-32768, 32767] — the documented behavior.
///
/// # Example
/// ```mbt check
/// test {
///   let synth = Synth::new()
///   let pitch = @music.Pitch::from_midi(midi=69).unwrap()
///   synth.trigger(
///     voice=0,
///     on={ track: 0, pitch, ticks: 8, instrument: @music.Instrument::celesta(), },
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
/// `on` is a sequencer note-start event. Its midi pitch selects the
/// precomputed phase increment (out-of-range midi is clamped into the table
/// defensively — `@music.Pitch` normally already enforces 0..=127); its
/// instrument supplies the oscillator waveform, the ADSR envelope, the
/// volume (clamped to 0..=100) and the optional vibrato. The voice then
/// sounds for `gate_samples` rendered samples before its release stage runs
/// automatically.
///
/// # Example
/// ```mbt check
/// test {
///   let synth = Synth::new()
///   let pitch = @music.Pitch::from_midi(midi=69).unwrap()
///   synth.trigger(
///     voice=0,
///     on={ track: 0, pitch, ticks: 8, instrument: @music.Instrument::strings(), },
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
  let inst = on.instrument
  let volume = if inst.volume < 0 {
    0
  } else if inst.volume > 100 {
    100
  } else {
    inst.volume
  }
  v.active = true
  v.waveform = inst.waveform
  v.preset = build_preset(inst)
  v.peak = VOICE_PEAK * volume / 100
  // A retrigger restarts the phase accumulator, vibrato LFO, noise LFSR and
  // envelope so the voice always sounds identical for identical notes.
  v.phase = 0
  v.inc = increment_table[clamped]
  // Vibrato: rate -> integer LFO increment (round-half of
  // 2^31 * rate_millihz / (1000 * SAMPLE_RATE) via Int64); depth -> detune
  // span proportional to this note's phase increment.
  match inst.vibrato {
    Some(vib) if vib.rate_millihz > 0 && vib.depth_cents > 0 => {
      let num = 2147483648L * Int64::from_int(vib.rate_millihz)
      let den = 1000L * Int64::from_int(SAMPLE_RATE)
      v.lfo_inc = ((num + den / 2L) / den).to_int().reinterpret_as_uint()
      v.vib_span = (Int64::from_int(v.inc) *
      Int64::from_int(vib.depth_cents) /
      1731L).to_int()
    }
    _ => {
      v.lfo_inc = 0
      v.vib_span = 0
    }
  }
  v.lfo_phase = 0
  v.lfsr = LFSR_SEED
  v.env = 0
  v.state = Attack
  v.gate = gate_samples
}

///|
/// Releases one voice early: it fades through its instrument's release stage
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
///     on={ track: 0, pitch, ticks: 8, instrument: @music.Instrument::strings(), },
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
  self.render_range(out~, offset=0, len=out.length())
}

///|
/// Range variant of `render`: writes `len` samples starting at
/// `out[offset]`, leaving the rest of `out` untouched. Renders exactly
/// `len` new samples of voice state — slicing a buffer this way produces
/// bit-identical output to rendering the whole span at once. Aborts when
/// `offset + len` exceeds the buffer (a caller bug); `len <= 0` is a no-op.
/// This is the primitive sample-accurate schedulers (the `Player`) use to
/// render up to an event boundary inside one buffer without copying.
pub fn Synth::render_range(
  self : Synth,
  out~ : FixedArray[Int],
  offset~ : Int,
  len~ : Int,
) -> Unit {
  if len <= 0 {
    return
  }
  if offset < 0 || offset + len > out.length() {
    abort(
      "Synth::render_range: [offset, offset + len) must fit the buffer, got offset=\{offset} len=\{len} buffer=\{out.length()}",
    )
  }
  for i in 0..<len {
    let mut total = 0
    for k in 0..<VOICES {
      let v = self.voices[k]
      if v.active {
        total += v.next_sample()
      }
    }
    out[offset + i] = if total > PCM16_MAX {
      PCM16_MAX
    } else if total < PCM16_MIN {
      PCM16_MIN
    } else {
      total
    }
  }
}
