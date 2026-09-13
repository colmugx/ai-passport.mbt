///|
/// One note-start event delivered by the sequencer on its trigger tick.
///
/// `track` is the 0-based track index (at most four per AGENTS.md rule 7),
/// `pitch` is the sounding note (rests never trigger), `eighths` is the gate
/// length in eighth-ticks (from `Note.eighths`), and `waveform` comes from the
/// track's instrument.
pub(all) struct NoteOn {
  track : Int
  pitch : Pitch
  eighths : Int
  waveform : Waveform
} derive(Debug)

///|
/// Sums a track's `eighths` into its total timeline length in ticks.
fn track_length_ticks(notes : Array[Note]) -> Int {
  let mut total = 0
  for note in notes {
    total += note.eighths
  }
  total
}

///|
/// Song length in ticks: the longest track's cumulative sum (0 when the song
/// has no tracks or no notes).
fn song_length_ticks(song : Song) -> Int {
  let mut longest = 0
  for track in song.tracks {
    let total = track_length_ticks(track.notes)
    if total > longest {
      longest = total
    }
  }
  longest
}

///|
/// Rejects non-positive note durations. `Note` intentionally leaves duration
/// enforcement to the sequencer (see `note.mbt`), and the sequencer surface is
/// abort-based, so a bad duration aborts construction.
fn validate_durations(song : Song) -> Unit {
  for t, track in song.tracks {
    for k, note in track.notes {
      if note.eighths <= 0 {
        abort(
          "Sequencer: track \{t} note \{k} has non-positive duration \{note.eighths}; durations must be positive eighth-ticks",
        )
      }
    }
  }
}

///|
/// Walks a track's cumulative-sum timeline to position `pos` and returns the
/// index of the note sounding there together with the ticks already consumed
/// of it. Note `k` starts at the cumulative tick of notes `0..k-1`, so this
/// finds the last start boundary `<= pos`. When `pos` reaches the track's
/// total, the index equals `notes.length()` (the track is past its end).
fn walk_timeline(notes : Array[Note], pos : Int) -> (Int, Int) {
  let mut boundary = 0
  let mut index = 0
  while index < notes.length() && boundary + notes[index].eighths <= pos {
    boundary += notes[index].eighths
    index += 1
  }
  (index, pos - boundary)
}

///|
/// Deterministic 6/8 transport (AGENTS.md rule 7: at most four monophonic
/// voices). A tick is one 1/8 note. Each track is a monophonic melody line:
/// its timeline is the cumulative sum of its notes' `eighths`, and a track
/// past its end stays silent until the loop wraps.
///
/// The loop region defaults to the whole song: `length()` is the longest
/// track's total ticks, and an empty song has length 0, leaving the sequencer
/// permanently idle.
///
/// # Example
/// ```mbt check
/// test {
///   let track : Track = {
///     instrument: { name: "Celesta", waveform: Pulse12, },
///     notes: [{ pitch: Pitch::from_midi(midi=60), eighths: 2, }],
///   }
///   let song = Song::new(meter=Meter::six_eight(), tempo=Tempo::standard(), tracks=[
///     track,
///   ])
///   let seq = Sequencer::new(song~)
///   let events = seq.step()
///   inspect(events.length(), content="1")
///   inspect(events[0].pitch.midi, content="60")
///   inspect(seq.tick(), content="1")
/// }
/// ```
pub struct Sequencer {
  priv song : Song
  priv cursor : FixedArray[Int]
  priv offset : FixedArray[Int]
  priv mut tick : Int
  priv loop_start : Int
  priv loop_end : Int
}

///|
/// Shared constructor: a fresh sequencer sits at tick 0 with every track
/// cursor at note 0.
fn build_sequencer(song : Song, loop_start : Int, loop_end : Int) -> Sequencer {
  let track_count = song.tracks.length()
  {
    song,
    cursor: FixedArray::make(track_count, 0),
    offset: FixedArray::make(track_count, 0),
    tick: 0,
    loop_start,
    loop_end,
  }
}

///|
/// Builds a sequencer whose loop region is the whole song: tick 0 through the
/// longest track's total ticks (0 for an empty song, which stays idle
/// forever).
///
/// Aborts if any note has a non-positive `eighths` duration — `Note` leaves
/// duration enforcement to the sequencer.
pub fn Sequencer::new(song~ : Song) -> Sequencer {
  validate_durations(song)
  build_sequencer(song, 0, song_length_ticks(song))
}

///|
/// Builds a sequencer with an explicit loop region `[start, end)` in
/// eighth-ticks.
///
/// Aborts unless `0 <= start < end <= ` the song length in ticks: an `end`
/// beyond the song is rejected rather than clamped, keeping caller bugs loud.
/// Notes crossing `end` finish playing with the gate length they were
/// triggered with; triggering resumes at `start` on the first step of each
/// wrapped cycle, and note-starts before `start` never repeat.
pub fn Sequencer::new_with_loop(
  song~ : Song,
  start~ : Int,
  end~ : Int,
) -> Sequencer {
  validate_durations(song)
  let total = song_length_ticks(song)
  if start < 0 || end <= start || end > total {
    abort(
      "Sequencer::new_with_loop: require 0 <= start < end <= song length \{total}, got start=\{start} end=\{end}",
    )
  }
  build_sequencer(song, start, end)
}

///|
/// The song this sequencer plays.
pub fn Sequencer::song(self : Sequencer) -> Song {
  self.song
}

///|
/// Current transport position, always in `[0, length())`. A fresh sequencer
/// sits at tick 0.
pub fn Sequencer::tick(self : Sequencer) -> Int {
  self.tick
}

///|
/// Loop length in eighth-ticks. 0 means an empty song.
pub fn Sequencer::length(self : Sequencer) -> Int {
  self.loop_end
}

///|
/// Advances the transport by one eighth-tick and returns every note-start the
/// transport crossed on that tick, ordered by track index.
///
/// Note `k` of a track starts at the cumulative tick of notes `0..k-1`; its
/// `NoteOn` is reported by the step after which `tick()` equals that start
/// boundary plus one — in particular note 0, which starts at tick 0, is
/// reported by the first `step()` call. Rests never trigger. When the
/// transport would move onto tick `loop_end`, it wraps to `loop_start` and
/// every track's cursor is recomputed to `loop_start` by walking the
/// cumulative sums; note-starts at `loop_start` are triggered again on the
/// first step of the wrapped cycle, and starts before `loop_start` never
/// repeat. Notes crossing the loop end finish playing with the gate length
/// they were triggered with. On an empty song (length 0) `step()` is a no-op
/// returning `[]`.
pub fn Sequencer::step(self : Sequencer) -> Array[NoteOn] {
  if self.loop_end == 0 {
    return []
  }
  let events : Array[NoteOn] = []
  for t, track in self.song.tracks {
    let notes = track.notes
    if self.cursor[t] >= notes.length() {
      continue // past the end: silent until the loop wraps
    }
    self.offset[t] += 1
    let note = notes[self.cursor[t]]
    if self.offset[t] == 1 {
      // The transport crossed this note's start boundary one tick ago and the
      // note is now sounding its first tick.
      match note.pitch {
        Some(pitch) =>
          events.push({
            track: t,
            pitch,
            eighths: note.eighths,
            waveform: track.instrument.waveform,
          })
        None => () // rests never trigger
      }
    }
    // Consume notes the transport finished on this tick. Durations are
    // enforced positive at construction, so at most one boundary is crossed.
    while self.cursor[t] < notes.length() &&
          self.offset[t] >= notes[self.cursor[t]].eighths {
      self.offset[t] -= notes[self.cursor[t]].eighths
      self.cursor[t] += 1
    }
  }
  self.tick = self.tick + 1
  if self.tick >= self.loop_end {
    // Transition onto loop_end: wrap the transport and recompute every
    // track's cursor to loop_start by walking the cumulative sums. Note-starts
    // at loop_start retrigger on the next step — the first of the new cycle —
    // through the same offset rule as everywhere else.
    self.tick = self.loop_start
    for t, track in self.song.tracks {
      let (index, consumed) = walk_timeline(track.notes, self.loop_start)
      self.cursor[t] = index
      self.offset[t] = consumed
    }
  }
  events
}
