///|
/// Waveforms available to v0.1 voices (`docs/MUSIC.md`).
///
/// `Pulse12`, `Pulse25`, and `Pulse50` are pulse waves with 12.5%, 25%, and
/// 50% duty cycles respectively; `Triangle` is a triangle wave; `Noise` is
/// white noise.
///
/// A waveform is only the oscillator shape. Musical articulation — how the
/// amplitude and pitch move over time — lives on the `Instrument`.
pub(all) enum Waveform {
  Pulse12
  Pulse25
  Pulse50
  Triangle
  Noise
} derive(Debug)

///|
/// An instrument voice: a musical role (name, oscillator waveform, envelope,
/// volume, optional vibrato) that a track plays with.
///
/// Names describe musical roles (e.g. "Celesta", "Woodwind Lead"), not
/// acoustic emulation (`docs/MUSIC.md`). The synth derives ALL runtime
/// envelope/vibrato/volume behavior from the instrument — never from the
/// waveform alone.
///
/// `volume` is a percentage of the voice peak; values outside 0..=100 are
/// clamped by the synth at trigger time.
pub(all) struct Instrument {
  name : String
  waveform : Waveform
  envelope : Envelope
  volume : Int
  vibrato : Vibrato?
} derive(Debug)

///|
/// Short plucked celesta/harp role (Pulse12): instant attack, ~0.24 s decay
/// to 6%, 0.13 s release.
pub fn Instrument::celesta() -> Instrument {
  {
    name: "Celesta",
    waveform: Pulse12,
    envelope: { attack_ms: 0, decay_ms: 240, sustain: 4096, release_ms: 128, },
    volume: 100,
    vibrato: None,
  }
}

///|
/// Lyrical woodwind lead role (Pulse25): 1 ms attack, 0.06 s decay to 88%,
/// 0.26 s release, light 5 Hz vibrato at ~13 cents.
pub fn Instrument::woodwind() -> Instrument {
  {
    name: "Woodwind Lead",
    waveform: Pulse25,
    envelope: { attack_ms: 1, decay_ms: 64, sustain: 57344, release_ms: 256, },
    volume: 100,
    vibrato: Some({ rate_millihz: 5000, depth_cents: 13, }),
  }
}

///|
/// Slower lyrical strings role (Pulse50): 64 ms attack, 0.13 s decay to 88%,
/// 0.51 s release.
pub fn Instrument::strings() -> Instrument {
  {
    name: "Lyrical Strings",
    waveform: Pulse50,
    envelope: { attack_ms: 64, decay_ms: 128, sustain: 57344, release_ms: 512, },
    volume: 100,
    vibrato: None,
  }
}

///|
/// Low strings/bass foundation role (Triangle): 16 ms attack, 0.13 s decay
/// to 75%, 0.34 s release.
pub fn Instrument::low_strings() -> Instrument {
  {
    name: "Low Strings",
    waveform: Triangle,
    envelope: { attack_ms: 16, decay_ms: 128, sustain: 49152, release_ms: 341, },
    volume: 100,
    vibrato: None,
  }
}
