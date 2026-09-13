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
/// A piece of music: a meter, a tempo, a tick resolution, and up to four
/// tracks.
///
/// `ticks_per_eighth` is the timing resolution: one eighth note lasts that
/// many song ticks, so `Note.ticks` and the sequencer/loop bounds are all
/// expressed in song ticks. The v0.1 default is 4 (sixteenth = 2 ticks,
/// thirty-second = 1 tick).
pub(all) struct Song {
  meter : Meter
  tempo : Tempo
  ticks_per_eighth : Int
  tracks : Array[Track]
} derive(Debug)

///|
/// Validated constructor. Raises SongError::TooManyVoices iff more than four
/// tracks; aborts on a non-positive `ticks_per_eighth` (a resolution of 0
/// would divide time by zero — a programmer error, not a runtime condition).
/// Zero tracks is allowed. `ticks_per_eighth` defaults to 4. Data model only
/// — no DSP, no scheduling.
pub fn Song::new(
  meter~ : Meter,
  tempo~ : Tempo,
  tracks~ : Array[Track],
  ticks_per_eighth? : Int = 4,
) -> Song raise SongError {
  if tracks.length() > 4 {
    raise SongError::TooManyVoices
  }
  if ticks_per_eighth <= 0 {
    abort("Song::new: ticks_per_eighth must be > 0, got \{ticks_per_eighth}")
  }
  { meter, tempo, ticks_per_eighth, tracks, }
}
