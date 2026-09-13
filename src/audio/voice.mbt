///|
/// Full scale of the 16-bit fixed-point envelope fraction: 0..65536 maps to
/// amplitude 0.0..1.0, so one envelope unit is 1/65536 and applying it is a
/// multiply plus `>> 16` (integer, allocation-free).
const ENV_FULL : Int = 65536

///|
/// Per-voice peak amplitude at volume 100. Chosen so four simultaneous
/// full-level voices sum to 48000 and clip into PCM16 only when loud
/// instruments stack — clamping is then the documented behavior (see
/// `Synth::render`). The instrument's `volume` percentage scales this down
/// at trigger time.
const VOICE_PEAK : Int = 12000

///|
/// Phase accumulator period 2^31. The accumulator stays in [0, PHASE_PERIOD)
/// and every addition is followed by an explicit wrap check, so Int overflow
/// is never relied upon. Stored as UInt because 2^31 does not fit a positive
/// 32-bit Int.
const PHASE_PERIOD : UInt = 2147483648

///|
/// Milliseconds to samples at the 16000 Hz baseline: one millisecond is
/// `SAMPLE_RATE / 1000` samples (exactly 16 at 16000 Hz). Sub-millisecond
/// envelope times therefore quantize; `ms <= 0` yields 0 samples (instant).
fn ms_to_samples(ms : Int) -> Int {
  if ms <= 0 {
    0
  } else {
    ms * (SAMPLE_RATE / 1000)
  }
}

///|
/// Seed of the 16-bit noise LFSR (taps 16/14/13/11, maximal length 65535).
/// Every trigger restarts from this seed, so two identical trigger+render
/// sequences produce identical noise buffers.
const LFSR_SEED : Int = 0xACE1

///|
/// PCM16 bounds used when mixing voices (`Synth::render`).
const PCM16_MAX : Int = 32767

///|
/// PCM16 lower bound used when mixing voices (`Synth::render`).
const PCM16_MIN : Int = -32768

///|
/// Envelope stage of one voice.
priv enum EnvState {
  Attack
  Decay
  Sustain
  Release
}

///|
/// Envelope with all rates precomputed as per-sample integer steps of the
/// 16-bit fixed-point amplitude fraction (0..65536 = 0.0..1.0), so the hot
/// path never divides. Built once per trigger from the instrument's
/// millisecond `Envelope` (see `build_preset`); times below are per-sample
/// steps at SAMPLE_RATE = 16000 Hz.
priv struct EnvelopePreset {
  /// Amplitude units added per sample while attacking
  /// (65536 / attack_samples).
  attack_step : Int
  /// Amplitude units removed per sample while decaying toward `sustain`.
  decay_step : Int
  /// Level held after the decay, in amplitude units.
  sustain : Int
  /// Amplitude units removed per sample while releasing.
  release_step : Int
}

///|
/// Converts an instrument's millisecond envelope into per-sample integer
/// steps (one division each, once per trigger — never per sample):
///
/// - `attack_ms`/`release_ms` of 0 mean instant, expressed as a full-scale
///   step (the stage finishes inside one sample).
/// - `decay_ms` moves the level from full scale down to `sustain`, so
///   `decay_step = (65536 - sustain) / decay_samples`.
/// - `sustain` is clamped into 0..=65536.
/// - A positive stage whose integer division floors to 0 (any duration above
///   65536 samples, i.e. ~4.1 s at 16000 Hz) is clamped to a 1-unit step, so
///   quantization can never permanently stall a voice; the stage then simply
///   lasts 65536 samples.
fn build_preset(instrument : @music.Instrument) -> EnvelopePreset {
  let env = instrument.envelope
  let sustain = if env.sustain < 0 {
    0
  } else if env.sustain > ENV_FULL {
    ENV_FULL
  } else {
    env.sustain
  }
  let attack_samples = ms_to_samples(env.attack_ms)
  let attack_step = if attack_samples <= 0 {
    ENV_FULL
  } else {
    (ENV_FULL / attack_samples).max(1)
  }
  let decay_samples = ms_to_samples(env.decay_ms)
  let decay_span = ENV_FULL - sustain
  let decay_step = if decay_samples <= 0 || decay_span <= 0 {
    ENV_FULL
  } else {
    (decay_span / decay_samples).max(1)
  }
  let release_samples = ms_to_samples(env.release_ms)
  let release_step = if release_samples <= 0 {
    ENV_FULL
  } else {
    (ENV_FULL / release_samples).max(1)
  }
  { attack_step, decay_step, sustain, release_step, }
}

///|
/// One monophonic synth voice. Private implementation detail of `Synth`.
/// All mutable state is integer; the per-sample path allocates nothing.
priv struct Voice {
  /// Active voices are mixed by `Synth::render`; released-to-silence voices
  /// flip this off and are skipped.
  mut active : Bool
  /// Waveform (oscillator shape) chosen at trigger time from the
  /// instrument.
  mut waveform : @music.Waveform
  /// Envelope preset captured at trigger time from the instrument.
  mut preset : EnvelopePreset
  /// Peak amplitude for this voice: VOICE_PEAK scaled by the instrument
  /// volume percentage.
  mut peak : Int
  /// Fixed-point phase accumulator in [0, PHASE_PERIOD), explicit wrap.
  mut phase : UInt
  /// Base phase increment from the midi table (positive, < 2^31).
  mut inc : Int
  /// Vibrato detune span: the maximum phase-increment delta, proportional
  /// to `inc` (0 = vibrato off).
  mut vib_span : Int
  /// Vibrato LFO phase increment per sample (0 = vibrato off).
  mut lfo_inc : UInt
  /// Vibrato LFO phase in [0, PHASE_PERIOD), advanced only when vibrato
  /// is on.
  mut lfo_phase : UInt
  /// 16-bit noise LFSR state, kept masked to the low 16 bits.
  mut lfsr : Int
  /// 16-bit fixed-point amplitude fraction, 0..ENV_FULL.
  mut env : Int
  /// Current envelope stage.
  mut state : EnvState
  /// Remaining gate samples; exhaustion switches to Release automatically.
  mut gate : Int
}

///|
/// Builds an idle voice. Its placeholder preset/peak are never read while
/// the voice is idle (`Synth::render` skips inactive voices);
/// `Synth::trigger` overwrites every field before the voice is heard.
fn Voice::idle() -> Voice {
  {
    active: false,
    waveform: @music.Pulse50,
    preset: { attack_step: 1, decay_step: 1, sustain: 0, release_step: 1, },
    peak: 0,
    phase: 0,
    inc: 0,
    vib_span: 0,
    lfo_inc: 0,
    lfo_phase: 0,
    lfsr: LFSR_SEED,
    env: 0,
    state: Sustain,
    gate: 0,
  }
}

///|
/// Advances the envelope state machine by one sample, then counts the gate
/// down unless the voice is already releasing. Gate exhaustion (or an early
/// `Synth::release`) enters Release; Release reaching zero deactivates the
/// voice so later renders stay silent.
fn Voice::advance_envelope(self : Voice) -> Unit {
  let preset = self.preset
  match self.state {
    Attack => {
      self.env += preset.attack_step
      if self.env >= ENV_FULL {
        self.env = ENV_FULL
        self.state = Decay
      }
      self.count_gate()
    }
    Decay => {
      self.env -= preset.decay_step
      if self.env <= preset.sustain {
        self.env = preset.sustain
        self.state = Sustain
      }
      self.count_gate()
    }
    Sustain => self.count_gate()
    Release => {
      self.env -= preset.release_step
      if self.env <= 0 {
        self.env = 0
        self.active = false
      }
    }
  }
}

///|
/// Counts one gate sample down; exhaustion switches the voice into Release
/// automatically ("gate exhaustion enters release").
fn Voice::count_gate(self : Voice) -> Unit {
  self.gate -= 1
  if self.gate <= 0 {
    self.state = Release
  }
}

///|
/// Produces this sample's contribution (already envelope-scaled) and
/// advances every per-sample counter. Pure integer, zero allocation:
/// envelope steps, waveform selection, phase/LFO/LFSR advances are all
/// fixed-point arithmetic. The phase increment add wraps explicitly at
/// PHASE_PERIOD — Int overflow is never relied upon.
fn Voice::next_sample(self : Voice) -> Int {
  self.advance_envelope()
  if !self.active {
    return 0
  }
  // Top 16 bits of the phase are the position inside one cycle, 0..65535.
  let cycle = (self.phase >> 15).reinterpret_as_int()
  let peak = self.peak
  let value : Int = match self.waveform {
    @music.Pulse12 => if cycle < 8192 { peak } else { -peak }
    @music.Pulse25 => if cycle < 16384 { peak } else { -peak }
    @music.Pulse50 => if cycle < 32768 { peak } else { -peak }
    @music.Triangle =>
      if cycle < 32768 {
        -peak + cycle * 2 * peak / 32768
      } else {
        peak - (cycle - 32768) * 2 * peak / 32768
      }
    @music.Noise =>
      // Read the current LFSR top bit; the register advances below.
      if ((self.lfsr >> 15) & 1) == 1 {
        peak
      } else {
        -peak
      }
  }
  // 16-bit fixed-point envelope: amplitude = value * env / 65536.
  let amplified = (value * self.env) >> 16
  // Vibrato (only when the instrument carries one): light triangle-LFO
  // detune of the phase increment. The LFO fraction lfo is centered in
  // [-16384, 16384]; each side is shifted right by 7 so the product stays
  // inside Int while the maximum delta still reaches the configured span.
  let inc_now = if self.vib_span > 0 {
    let tri = (self.lfo_phase >> 15).reinterpret_as_int()
    let folded = if tri < 32768 { tri } else { 65536 - tri }
    let lfo = folded - 16384
    self.inc + (self.vib_span >> 7) * (lfo >> 7)
  } else {
    self.inc
  }
  // Advance the phase with an explicit wrap at 2^31. phase < 2^31 and
  // inc < 2^31, so the UInt sum is < 2^32 and one conditional subtraction
  // restores [0, 2^31). No overflow is relied upon on either side.
  let next = self.phase + inc_now.reinterpret_as_uint()
  self.phase = if next >= PHASE_PERIOD { next - PHASE_PERIOD } else { next }
  if self.vib_span > 0 {
    let lfo_next = self.lfo_phase + self.lfo_inc
    self.lfo_phase = if lfo_next >= PHASE_PERIOD {
      lfo_next - PHASE_PERIOD
    } else {
      lfo_next
    }
  }
  if self.waveform is @music.Noise {
    // 16-bit maximal-length LFSR (taps 16/14/13/11), advanced once per
    // sample, masked back to 16 bits. Deterministic from LFSR_SEED.
    let bit = (
        self.lfsr ^ (self.lfsr >> 2) ^ (self.lfsr >> 3) ^ (self.lfsr >> 5)
      ) &
      1
    self.lfsr = ((self.lfsr >> 1) | (bit << 15)) & 0xFFFF
  }
  amplified
}
