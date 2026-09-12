///|
/// Waveforms available to v0.1 voices (`docs/MUSIC.md`).
///
/// `Pulse12`, `Pulse25`, and `Pulse50` are pulse waves with 12.5%, 25%, and
/// 50% duty cycles respectively; `Triangle` is a triangle wave; `Noise` is
/// white noise.
pub(all) enum Waveform {
  Pulse12
  Pulse25
  Pulse50
  Triangle
  Noise
} derive(Debug)

///|
/// An instrument voice: a musical role name plus the waveform that voice
/// plays.
///
/// Names describe musical roles (e.g. "Celesta", "Woodwind Lead"), not
/// acoustic emulation (`docs/MUSIC.md`).
pub(all) struct Instrument {
  name : String
  waveform : Waveform
} derive(Debug)
