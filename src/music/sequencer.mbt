///|
/// One note-start event delivered by the sequencer on its trigger tick.
///
/// `track` is the 0-based track index (at most four per AGENTS.md rule 7),
/// `pitch` is the sounding note (rests never trigger), `ticks` is the gate
/// length in song ticks (from `Note.ticks`), and `instrument` is the track's
/// instrument — the synth derives envelope, volume and vibrato from it.
pub(all) struct NoteOn {
  track : Int
  pitch : Pitch
  ticks : Int
  instrument : Instrument
} derive(Debug)

///|
/// Sums a track's `ticks` into its total timeline length in song ticks.
fn track_length_ticks(notes : Array[Note]) -> Int {
  let mut total = 0
  for note in notes {
    total += note.ticks
  }
  total
}

///|
/// Song length in song ticks: the longest track's cumulative sum (0 when the
/// song has no tracks or no notes).
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
      if note.ticks <= 0 {
        abort(
          "Sequencer: track \{t} note \{k} has non-positive duration \{note.ticks}; durations must be positive song ticks",
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
  while index < notes.length() && boundary + notes[index].ticks <= pos {
    boundary += notes[index].ticks
    index += 1
  }
  (index, pos - boundary)
}

///|
/// Deterministic 6/8 transport (AGENTS.md rule 7: at most four monophonic
/// voices). A tick is one song tick — `1/ticks_per_eighth` of an eighth note
/// (`Song.ticks_per_eighth`; a 1/32 note at the default resolution of 4).
/// Each track is a monophonic melody line: its timeline is the cumulative
/// sum of its notes' `ticks`, and a track past its end stays silent until
/// the loop wraps.
///
/// The transport model is *arrival-based*: `step()` moves the transport onto
/// the next tick and reports the note-starts whose start boundary is the tick
/// it lands on. A fresh sequencer sits at tick 0 without having fired it —
/// its first `step()` is the arrival at tick 0 (`tick()` stays 0), so a note
/// starting at tick 0 is reported before any transport time has elapsed. An
/// audio player calls that first step before rendering its first sample and
/// every later step exactly on its tick boundary, which puts the first
/// audible sample at output sample 0.
///
/// The loop region defaults to the whole song: `length()` is the longest
/// track's total ticks, and an empty song has length 0, leaving the sequencer
/// permanently idle.
///
/// # Example
/// ```mbt check
/// test {
///   let track : Track = {
///     instrument: Instrument::celesta(),
///     notes: [{ pitch: Pitch::from_midi(midi=60), ticks: 8, }],
///   }
///   let song = Song::new(meter=Meter::six_eight(), tempo=Tempo::standard(), tracks=[
///     track,
///   ])
///   let seq = Sequencer::new(song~)
///   // The first step is the arrival at tick 0: the C4 note-start fires
///   // before any transport time has elapsed.
///   let events = seq.step()
///   inspect(events.length(), content="1")
///   inspect(events[0].pitch.midi, content="60")
///   inspect(seq.tick(), content="0")
/// }
/// ```
pub struct Sequencer {
  priv song : Song
  priv cursor : FixedArray[Int]
  priv offset : FixedArray[Int]
  priv mut tick : Int
  priv mut arrived : Bool
  priv loop_start : Int
  priv loop_end : Int
}

///|
/// Shared constructor: a fresh sequencer sits at tick 0 with every track
/// cursor at note 0 and the tick-0 arrival not yet fired.
fn build_sequencer(song : Song, loop_start : Int, loop_end : Int) -> Sequencer {
  let track_count = song.tracks.length()
  {
    song,
    cursor: FixedArray::make(track_count, 0),
    offset: FixedArray::make(track_count, 0),
    tick: 0,
    arrived: false,
    loop_start,
    loop_end,
  }
}

///|
/// Builds a sequencer whose loop region is the whole song: tick 0 through the
/// longest track's total ticks (0 for an empty song, which stays idle
/// forever).
///
/// Aborts if any note has a non-positive `ticks` duration — `Note` leaves
/// duration enforcement to the sequencer.
pub fn Sequencer::new(song~ : Song) -> Sequencer {
  validate_durations(song)
  build_sequencer(song, 0, song_length_ticks(song))
}

///|
/// Builds a sequencer with an explicit loop region `[start, end)` in
/// song ticks.
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
/// Current transport position in song ticks, always inside the loop region
/// `[loop_start, loop_end)` — which equals `0..<length()` only when the
/// loop starts at tick 0. A fresh sequencer sits at tick 0, and its first
/// `step()` is the arrival at tick 0 (the position only moves on the second
/// step).
pub fn Sequencer::tick(self : Sequencer) -> Int {
  self.tick
}

///|
/// Loop length in song ticks: `loop_end - loop_start`, the number of ticks
/// one full cycle plays. 0 means an empty song. The transport position is
/// NOT an index into `0..<length()` when the loop starts after tick 0 — it
/// ranges over `[loop_start, loop_end)`.
pub fn Sequencer::length(self : Sequencer) -> Int {
  self.loop_end - self.loop_start
}

///|
/// Advances the transport to the next song tick and reports every note-start
/// whose start boundary is the tick the transport lands on, writing them into
/// the caller's `events` buffer and returning the count. This is the
/// realtime-safe step: it allocates nothing, so an audio player can call it
/// on every tick boundary with a preallocated buffer.
///
/// The contract is loud, not lossy: `events` must hold at least one slot per
/// song track (at most four per AGENTS.md rule 7 — each monophonic track
/// starts at most one note per tick), and a smaller buffer aborts. Every slot
/// is overwritten on each call — slots at indices `count..` are reset to
/// `None`, so stale events can never leak into a later step. Events are
/// ordered by track index.
///
/// Note `k` of a track starts at the cumulative tick of notes `0..k-1`; its
/// `NoteOn` is reported by the step after which `tick()` equals that start
/// boundary. In particular the first `step_into` on a fresh sequencer is the
/// arrival at tick 0 (`tick()` stays 0), where note 0 fires — a player calls
/// it before rendering its first sample so tick-0 notes sound from sample 0.
/// Rests never trigger. When the transport would move onto tick `loop_end`,
/// it wraps to `loop_start` and every track's cursor is recomputed to
/// `loop_start` by walking the cumulative sums; the wrapped arrival reports
/// note-starts exactly at `loop_start` again, starts before `loop_start`
/// never repeat, and notes crossing the loop end finish playing with the
/// gate length they were triggered with. On an empty song (length 0)
/// `step_into` is a no-op returning 0.
pub fn Sequencer::step_into(
  self : Sequencer,
  events : FixedArray[NoteOn?],
) -> Int {
  if events.length() < self.song.tracks.length() {
    abort(
      "Sequencer::step_into: the event buffer holds \{events.length()} slots but the song has \{self.song.tracks.length()} tracks; provide at least one slot per track (at most four)",
    )
  }
  for i in 0..<events.length() {
    events[i] = None
  }
  if self.loop_end == 0 {
    return 0
  }
  if !self.arrived {
    // First step: the transport arrives at tick 0. The cursors already sit
    // at (note 0, 0 ticks consumed) from construction, so the shared arrival
    // rule below reports exactly the tick-0 note-starts, and tick() stays 0.
    self.arrived = true
  } else {
    for t, track in self.song.tracks {
      let notes = track.notes
      if self.cursor[t] >= notes.length() {
        continue // past the end: silent until the loop wraps
      }
      self.offset[t] += 1
      // Consume notes the transport finished on this tick. Durations are
      // enforced positive at construction, so at most one boundary is crossed.
      while self.cursor[t] < notes.length() &&
            self.offset[t] >= notes[self.cursor[t]].ticks {
        self.offset[t] -= notes[self.cursor[t]].ticks
        self.cursor[t] += 1
      }
    }
    self.tick = self.tick + 1
    if self.tick >= self.loop_end {
      // Transition onto loop_end: wrap the transport and recompute every
      // track's cursor to loop_start by walking the cumulative sums. The
      // wrapped arrival re-reports note-starts exactly at loop_start through
      // the same offset rule as everywhere else.
      self.tick = self.loop_start
      for t, track in self.song.tracks {
        let (index, consumed) = walk_timeline(track.notes, self.loop_start)
        self.cursor[t] = index
        self.offset[t] = consumed
      }
    }
  }
  // Arrival: a track fires its current note exactly when the transport lands
  // on the note's start boundary (0 ticks consumed of it). A mid-note landing
  // (loop_start inside a long note) has consumed > 0 and stays silent.
  let mut count = 0
  for t, track in self.song.tracks {
    if self.cursor[t] < track.notes.length() && self.offset[t] == 0 {
      let note = track.notes[self.cursor[t]]
      match note.pitch {
        Some(pitch) => {
          events[count] = Some({
            track: t,
            pitch,
            ticks: note.ticks,
            instrument: track.instrument,
          })
          count += 1
        }
        None => () // rests never trigger
      }
    }
  }
  count
}

///|
/// Convenience variant of `step_into` that returns a fresh `Array[NoteOn]`.
/// Allocates on every call — fine for tests, tools and offline timing math,
/// but realtime audio paths must use `step_into` with a preallocated buffer.
pub fn Sequencer::step(self : Sequencer) -> Array[NoteOn] {
  let buffer : FixedArray[NoteOn?] = FixedArray::make(
    self.song.tracks.length(),
    None,
  )
  let count = self.step_into(buffer)
  let events : Array[NoteOn] = []
  for i in 0..<count {
    match buffer[i] {
      Some(event) => events.push(event)
      None => () // unreachable: slots below count are always Some
    }
  }
  events
}
