///|
/// ADSR envelope of an `Instrument`.
///
/// Times are milliseconds at the 16000 Hz baseline (one millisecond is 16
/// samples); sub-millisecond values quantize (an `attack_ms` of 0 is an
/// instant attack). `sustain` is the held level as a 16-bit fixed-point
/// amplitude fraction: 0..65536 maps to 0.0..1.0 of the voice peak.
pub(all) struct Envelope {
  attack_ms : Int
  decay_ms : Int
  sustain : Int
  release_ms : Int
} derive(Debug)

///|
/// Pitch vibrato settings of an `Instrument`.
///
/// `rate_millihz` is the triangle-LFO rate in millihertz (5000 = 5 Hz).
/// `depth_cents` is the peak detune in cents, applied as the linear
/// approximation `depth/1731` of the phase increment (`ln(2)/1200`).
pub(all) struct Vibrato {
  rate_millihz : Int
  depth_cents : Int
} derive(Debug)
