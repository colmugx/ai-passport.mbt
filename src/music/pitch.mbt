///|
/// A chromatic pitch stored as a MIDI note number in `0..=127`.
///
/// Construct via `Pitch::from_midi`, which rejects out-of-range numbers.
///
/// # Example
/// ```mbt check
/// test {
///   debug_inspect(Pitch::from_midi(midi=69), content="Some({ midi: 69 })")
///   debug_inspect(Pitch::from_midi(midi=128), content="None")
/// }
/// ```
pub(all) struct Pitch {
  midi : Int
} derive(Debug)

///|
/// Builds a pitch from a MIDI note number.
///
/// Returns `Some` iff `0 <= midi <= 127`, otherwise `None`.
pub fn Pitch::from_midi(midi~ : Int) -> Pitch? {
  if midi >= 0 && midi <= 127 {
    Some({ midi, })
  } else {
    None
  }
}
