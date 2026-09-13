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
/// Envelope with attack and decay rates precomputed as Bresenham ramp parameters of the
/// 16-bit fixed-point amplitude fraction (0..65536 = 0.0..1.0), so the hot
/// path never divides and every stage reaches its target amplitude exactly
/// at its requested sample duration. Release rates are computed from the
/// current voice level when release begins. Built once per trigger from the
/// instrument's millisecond `Envelope` (see `build_preset`).
///
/// A stage that must move `span` units over `n` samples carries:
/// - `step`: the whole units applied every sample (`span / n`),
/// - `rem`: the leftover units (`span % n`), accumulated in the voice's
///   error register, adding one extra unit whenever it fills up — so the
///   ramp lands on the target at sample `n` exactly, even when `span < n`
///   (a long, small-amplitude ramp then advances through the remainder
///   instead of flooring to a stalled zero step).
priv struct EnvelopePreset {
  /// Amplitude units added per sample while attacking (65536 /
  /// attack_samples, whole part).
  attack_step : Int
  /// Attack remainder units accumulated into the error register.
  attack_rem : Int
  /// Attack stage length in samples (the error register's modulus).
  attack_samples : Int
  /// Amplitude units removed per sample while decaying toward `sustain`
  /// ((65536 - sustain) / decay_samples, whole part).
  decay_step : Int
  /// Decay remainder units accumulated into the error register.
  decay_rem : Int
  /// Decay stage length in samples (the error register's modulus).
  decay_samples : Int
  /// Level held after the decay, in amplitude units.
  sustain : Int
  /// Release stage length in samples (the error register's modulus).
  release_samples : Int
}

///|
/// Converts an instrument's millisecond envelope into per-sample integer
/// Bresenham ramp parameters (a handful of divisions/divmods, once per
/// trigger — never per sample):
///
/// - `attack_ms`/`release_ms` of 0 mean instant (one sample at the stage
///   boundary).
/// - `decay_ms` moves the level from full scale down to `sustain`, so the
///   decay ramp spans `65536 - sustain` units.
/// - `sustain` is clamped into 0..=65536.
/// - Because the remainder is carried, a positive stage can never stall:
///   even `0 < span < n` advances one unit every `n / span` samples and
///   reaches its target exactly at sample `n`. Millisecond times quantize
///   to samples (`ms * SAMPLE_RATE / 1000`, exact at 16000 Hz) — the ramp
///   is exact for the quantized duration.
fn build_preset(instrument : @music.Instrument) -> EnvelopePreset {
  let env = instrument.envelope
  let sustain = if env.sustain < 0 {
    0
  } else if env.sustain > ENV_FULL {
    ENV_FULL
  } else {
    env.sustain
  }
  // Splits `span` units over `n` samples into (whole step, remainder,
  // stage length); a non-positive n means instant, so the whole span
  // applies in one sample.
  fn ramp(span : Int, n : Int) -> (Int, Int, Int) {
    if n <= 0 {
      (span, 0, 1)
    } else {
      (span / n, span % n, n)
    }
  }
  let (attack_step, attack_rem, attack_samples) = ramp(
    ENV_FULL,
    ms_to_samples(env.attack_ms),
  )
  let (decay_step, decay_rem, decay_samples) = ramp(
    ENV_FULL - sustain,
    ms_to_samples(env.decay_ms),
  )
  let release_samples = if env.release_ms <= 0 {
    1
  } else {
    ms_to_samples(env.release_ms)
  }
  {
    attack_step,
    attack_rem,
    attack_samples,
    decay_step,
    decay_rem,
    decay_samples,
    sustain,
    release_samples,
  }
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
  /// Bresenham error register for the current envelope stage: accumulates
  /// the stage's remainder units and grants one extra step unit whenever it
  /// reaches the stage length. Reset on every stage transition (trigger,
  /// attack->decay, decay->sustain, release entry) so each stage's ramp is
  /// exact from its own start.
  mut env_err : Int
  /// Release ramp derived once from `env` at entry, so every positive
  /// release lasts its configured number of samples from any ADSR stage.
  mut release_step : Int
  mut release_rem : Int
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
    preset: {
      attack_step: 1,
      attack_rem: 0,
      attack_samples: 1,
      decay_step: 1,
      decay_rem: 0,
      decay_samples: 1,
      sustain: 0,
      release_samples: 1,
    },
    peak: 0,
    phase: 0,
    inc: 0,
    vib_span: 0,
    lfo_inc: 0,
    lfo_phase: 0,
    lfsr: LFSR_SEED,
    env: 0,
    env_err: 0,
    release_step: 0,
    release_rem: 0,
    state: Sustain,
    gate: 0,
  }
}

///|
/// Advances the envelope state machine by one sample, then counts the gate
/// down unless the voice is already releasing. Each stage moves by its
/// Bresenham step plus the error register's carried remainder, reaching its
/// target amplitude exactly at the requested stage length; the error
/// register resets on every stage transition. Gate exhaustion (or an early
/// `Synth::release`) enters Release; Release reaching zero deactivates the
/// voice so later renders stay silent. A positive stage can never stall:
/// the carried remainder keeps the level moving until the target is hit.
fn Voice::advance_envelope(self : Voice) -> Unit {
  let preset = self.preset
  match self.state {
    Attack => {
      self.env += preset.attack_step
      self.env_err += preset.attack_rem
      if self.env_err >= preset.attack_samples {
        self.env_err -= preset.attack_samples
        self.env += 1
      }
      if self.env >= ENV_FULL {
        self.env = ENV_FULL
        self.env_err = 0
        self.state = Decay
      }
      self.count_gate()
    }
    Decay => {
      self.env -= preset.decay_step
      self.env_err += preset.decay_rem
      if self.env_err >= preset.decay_samples {
        self.env_err -= preset.decay_samples
        self.env -= 1
      }
      if self.env <= preset.sustain {
        self.env = preset.sustain
        self.env_err = 0
        self.state = Sustain
      }
      self.count_gate()
    }
    Sustain => self.count_gate()
    Release => {
      self.env -= self.release_step
      self.env_err += self.release_rem
      if self.env_err >= preset.release_samples {
        self.env_err -= preset.release_samples
        self.env -= 1
      }
      if self.env <= 0 {
        self.env = 0
        self.active = false
      }
    }
  }
}

///|
/// Starts a release ramp from the current level. Division happens only at
/// this stage transition; the per-sample path uses the stored step and
/// remainder. A zero-millisecond release uses one step to silence.
fn Voice::enter_release(self : Voice) -> Unit {
  let n = self.preset.release_samples
  self.release_step = self.env / n
  self.release_rem = self.env % n
  self.env_err = 0
  self.state = Release
}

///|
/// Counts one gate sample down; exhaustion enters Release automatically.
fn Voice::count_gate(self : Voice) -> Unit {
  self.gate -= 1
  if self.gate <= 0 {
    self.enter_release()
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
