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
///
/// `Track` is an authoring value: build it freely (its `notes` array may be
/// reused across drafts), but it only becomes part of a playable song
/// through `Song::new`, which snapshots it — mutating the authoring arrays
/// afterwards never changes the song.
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
///
/// A `Song` is an **immutable snapshot**: `Song::new` deep-copies the
/// caller's tracks array and every track's notes array, so mutating the
/// authoring arrays afterwards can never change the song — and therefore can
/// never invalidate a `Sequencer` cursor walk or a `Player`'s event scratch
/// capacity, both of which are sized from the snapshot at construction.
/// Every field is private; read the snapshot through `meter()`, `tempo()`,
/// `ticks_per_eighth()` and `track_count()`.
pub struct Song {
  priv meter : Meter
  priv tempo : Tempo
  priv ticks_per_eighth : Int
  priv tracks : Array[Track]
} derive(Debug)

///|
/// Validated constructor producing an immutable snapshot. Raises
/// SongError::TooManyVoices iff more than four tracks; aborts on a
/// non-positive `ticks_per_eighth` (a resolution of 0 would divide time by
/// zero — a programmer error, not a runtime condition). Zero tracks is
/// allowed. `ticks_per_eighth` defaults to 4.
///
/// Deep-copies `tracks` and every track's `notes` array; `Track`/`Note`
/// values themselves are immutable data, so the copy is the whole story.
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
  let snapshot : Array[Track] = []
  for track in tracks {
    let notes : Array[Note] = []
    for note in track.notes {
      notes.push(note)
    }
    snapshot.push({ instrument: track.instrument, notes, })
  }
  { meter, tempo, ticks_per_eighth, tracks: snapshot, }
}

///|
/// The song's meter.
pub fn Song::meter(self : Song) -> Meter {
  self.meter
}

///|
/// The song's tempo.
pub fn Song::tempo(self : Song) -> Tempo {
  self.tempo
}

///|
/// The song's tick resolution: song ticks per eighth note.
pub fn Song::ticks_per_eighth(self : Song) -> Int {
  self.ticks_per_eighth
}

///|
/// Number of tracks in the snapshot (at most four per AGENTS.md rule 7).
pub fn Song::track_count(self : Song) -> Int {
  self.tracks.length()
}
