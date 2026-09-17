///|
/// The application's desired audio output state: `volume` is the
/// remembered setting (`0..=100`) and `muted` silences the output while the
/// setting is preserved. The application owns every control semantic; Host
/// adapters only mirror the state.
pub(all) struct AudioOutput {
  volume : Int
  muted : Bool
} derive(Eq, Debug)
