///|
/// One note (or rest) in a track.
///
/// `pitch = None` means a rest. `ticks` is the duration in song ticks — the
/// song's `ticks_per_eighth` divides one eighth note (default resolution 4:
/// an eighth lasts 4 ticks, a sixteenth 2, a thirty-second 1; in 6/8 a dotted
/// quarter lasts 12 ticks at the default resolution). Durations are expected
/// to be positive; enforcing that belongs to the sequencer, not this data
/// model.
///
/// # Example
/// ```mbt check
/// test {
///   let rest : Note = { pitch: None, ticks: 12, }
///   debug_inspect(rest, content="{ pitch: None, ticks: 12 }")
/// }
/// ```
pub(all) struct Note {
  pitch : Pitch?
  ticks : Int
} derive(Debug)
