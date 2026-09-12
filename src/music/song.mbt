///|
/// Domain errors for song construction (AGENTS.md rule 7: at most four
/// monophonic voices).
pub(all) suberror SongError {
  TooManyVoices
}

///|
/// Renders the error constructor name (e.g. `"TooManyVoices"`) so SongError
/// works with string interpolation and snapshot tests. (`derive(Show)` is
/// deprecated on this toolchain — warning 0027 — so Show is implemented
/// manually.)
pub impl Show for SongError with fn output(self, logger) {
  let name = match self {
    TooManyVoices => "TooManyVoices"
  }

  logger.write_string(name)
}

///|
/// One monophonic voice: an instrument plus its sequence of notes and rests.
pub(all) struct Track {
  instrument : Instrument
  notes : Array[Note]
} derive(Debug)

///|
/// A piece of music: a meter, a tempo, and up to four tracks.
pub(all) struct Song {
  meter : Meter
  tempo : Tempo
  tracks : Array[Track]
} derive(Debug)

///|
/// Validated constructor. Raises SongError::TooManyVoices iff more than four
/// tracks. Zero tracks is allowed. Data model only — no DSP, no scheduling.
pub fn Song::new(
  meter~ : Meter,
  tempo~ : Tempo,
  tracks~ : Array[Track],
) -> Song raise SongError {
  if tracks.length() > 4 {
    raise SongError::TooManyVoices
  }
  { meter, tempo, tracks, }
}
