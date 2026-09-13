///|
/// Full scale of the 16-bit fixed-point envelope fraction: 0..65536 maps to
/// amplitude 0.0..1.0, so one envelope unit is 1/65536 and applying it is a
/// multiply plus `>> 16` (integer, allocation-free).
const ENV_FULL : Int = 65536

///|
/// Per-voice waveform peak amplitude. Chosen so four simultaneous full-level
/// voices sum to 48000 and clip into PCM16 only when loud presets stack —
/// clamping is then the documented behavior (see `Synth::render`).
const VOICE_PEAK : Int = 12000

///|
/// Phase accumulator period 2^31. The accumulator stays in [0, PHASE_PERIOD)
/// and every addition is followed by an explicit wrap check, so Int overflow
/// is never relied upon. Stored as UInt because 2^31 does not fit a positive
/// 32-bit Int.
const PHASE_PERIOD : UInt = 2147483648

///|
/// Vibrato LFO phase increment: ~5.0 Hz triangle LFO at 16000 Hz
/// (2147483648 * 5.0 / 16000, rounded). Applied to Pulse25 only.
const LFO_INC : UInt = 671089

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
/// Envelope preset with all rates precomputed as per-sample integer steps of
/// the 16-bit fixed-point amplitude fraction (0..65536 = 0.0..1.0), so the
/// hot path never divides. Times below are at SAMPLE_RATE = 16000 Hz and
/// follow the musical roles in docs/MUSIC.md.
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
  /// Triangle-LFO pitch vibrato — Pulse25 (woodwind lead) only.
  vibrato : Bool
}

///|
/// Preset table per waveform. Documented constants (attack/decay/release in
/// samples at 16000 Hz, sustain as % of full scale):
///
/// - Pulse12 — celesta/harp, short plucked decay (MUSIC.md voice 1):
///   attack 4 samples, decay ~0.24 s to 6%, release 0.13 s.
/// - Pulse25 — woodwind lead, lyrical with light vibrato (voice 2):
///   attack 16 samples, decay 0.06 s to 88%, release 0.26 s.
/// - Pulse50 — lyrical strings, slower attack/release (voice 3):
///   attack 64 ms, decay 0.13 s to 88%, release 0.51 s.
/// - Triangle — low strings/bass foundation (voice 4):
///   attack 16 ms, decay 0.13 s to 75%, release 0.34 s.
/// - Noise — generic fast percussive voice:
///   attack instant, decay 30 ms to 6%, release 32 ms.
fn envelope_preset(waveform : @music.Waveform) -> EnvelopePreset {
  match waveform {
    @music.Pulse12 =>
      {
        attack_step: 16384,
        decay_step: 16,
        sustain: 4096,
        release_step: 32,
        vibrato: false,
      }
    @music.Pulse25 =>
      {
        attack_step: 4096,
        decay_step: 8,
        sustain: 57344,
        release_step: 16,
        vibrato: true,
      }
    @music.Pulse50 =>
      {
        attack_step: 64,
        decay_step: 4,
        sustain: 57344,
        release_step: 8,
        vibrato: false,
      }
    @music.Triangle =>
      {
        attack_step: 256,
        decay_step: 8,
        sustain: 49152,
        release_step: 12,
        vibrato: false,
      }
    @music.Noise =>
      {
        attack_step: 65536,
        decay_step: 128,
        sustain: 4096,
        release_step: 128,
        vibrato: false,
      }
  }
}

///|
/// One monophonic synth voice. Private implementation detail of `Synth`.
/// All mutable state is integer; the per-sample path allocates nothing.
priv struct Voice {
  /// Active voices are mixed by `Synth::render`; released-to-silence voices
  /// flip this off and are skipped.
  mut active : Bool
  /// Waveform chosen at trigger time.
  mut waveform : @music.Waveform
  /// Envelope preset captured at trigger time.
  mut preset : EnvelopePreset
  /// Fixed-point phase accumulator in [0, PHASE_PERIOD), explicit wrap.
  mut phase : UInt
  /// Base phase increment from the midi table (positive, < 2^31).
  mut inc : Int
  /// Vibrato LFO phase in [0, PHASE_PERIOD), advanced only when
  /// `preset.vibrato` is set.
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
/// Builds an idle voice. Its preset placeholder is never read while the
/// voice is idle (`Synth::render` skips inactive voices); `Synth::trigger`
/// overwrites every field before the voice is heard.
fn Voice::idle() -> Voice {
  {
    active: false,
    waveform: @music.Pulse50,
    preset: envelope_preset(@music.Pulse50),
    phase: 0,
    inc: 0,
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
  let preset = self.preset
  // Top 16 bits of the phase are the position inside one cycle, 0..65535.
  let cycle = (self.phase >> 15).reinterpret_as_int()
  let value : Int = match self.waveform {
    @music.Pulse12 => if cycle < 8192 { VOICE_PEAK } else { -VOICE_PEAK }
    @music.Pulse25 => if cycle < 16384 { VOICE_PEAK } else { -VOICE_PEAK }
    @music.Pulse50 => if cycle < 32768 { VOICE_PEAK } else { -VOICE_PEAK }
    @music.Triangle =>
      if cycle < 32768 {
        -VOICE_PEAK + cycle * 2 * VOICE_PEAK / 32768
      } else {
        VOICE_PEAK - (cycle - 32768) * 2 * VOICE_PEAK / 32768
      }
    @music.Noise =>
      // Read the current LFSR top bit; the register advances below.
      if ((self.lfsr >> 15) & 1) == 1 {
        VOICE_PEAK
      } else {
        -VOICE_PEAK
      }
  }
  // 16-bit fixed-point envelope: amplitude = value * env / 65536.
  let amplified = (value * self.env) >> 16
  // Pulse25 vibrato: light triangle-LFO detune of the phase increment
  // (~5 Hz LFO, ~13 cents peak — see LFO_INC; the intermediates cannot
  // overflow 2^31).
  let inc_now = if preset.vibrato {
    let tri = (self.lfo_phase >> 15).reinterpret_as_int()
    let folded = if tri < 32768 { tri } else { 65536 - tri }
    let lfo = (folded - 16384) >> 5 // [-512, 512]
    let delta = ((self.inc >> 9) * lfo) >> 7
    self.inc + delta
  } else {
    self.inc
  }
  // Advance the phase with an explicit wrap at 2^31. phase < 2^31 and
  // inc < 2^31, so the UInt sum is < 2^32 and one conditional subtraction
  // restores [0, 2^31). No overflow is relied upon on either side.
  let next = self.phase + inc_now.reinterpret_as_uint()
  self.phase = if next >= PHASE_PERIOD { next - PHASE_PERIOD } else { next }
  if preset.vibrato {
    let lfo_next = self.lfo_phase + LFO_INC
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
