///|
/// One note (or rest) in a track.
///
/// `pitch = None` means a rest. `eighths` is the duration in 1/8-note units;
/// in 6/8 a dotted quarter lasts `eighths = 3`. Durations are expected to be
/// positive; enforcing that belongs to the sequencer, not this data model.
///
/// # Example
/// ```mbt check
/// test {
///   let rest : Note = { pitch: None, eighths: 3, }
///   debug_inspect(rest, content="{ pitch: None, eighths: 3 }")
/// }
/// ```
pub(all) struct Note {
  pitch : Pitch?
  eighths : Int
} derive(Debug)
