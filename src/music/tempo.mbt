///|
/// Tempo counted in dotted-quarter beats per minute.
///
/// In 6/8 the dotted quarter (three eighth notes) is the large beat, so this
/// counts large beats per minute. The v0.1 default is ~76 (`docs/MUSIC.md`).
///
/// # Example
/// ```mbt check
/// test {
///   inspect(Tempo::standard().dotted_quarter_bpm, content="76")
/// }
/// ```
pub(all) struct Tempo {
  dotted_quarter_bpm : Int
} derive(Debug)

///|
/// The v0.1 standard tempo: 76 dotted-quarter BPM (`docs/MUSIC.md`).
pub fn Tempo::standard() -> Tempo {
  { dotted_quarter_bpm: 76, }
}
