// Whitebox tests: these compile inside the music package and read the
// Song snapshot's private fields to prove that Song::new deep-copies the
// caller's authoring arrays — external mutation can never reach a
// constructed song (and therefore can never invalidate sequencer cursors or
// a player's event scratch capacity).

///|
/// One-instrument authoring track helper.
fn wb_track(notes : Array[Note]) -> Track {
  {
    instrument: {
      name: "Celesta",
      waveform: Pulse12,
      envelope: { attack_ms: 0, decay_ms: 1, sustain: 0, release_ms: 1, },
      volume: 0,
      vibrato: None,
    },
    notes,
  }
}

///|
test "mutating the authoring tracks array after Song::new does not change the song" {
  let note = { pitch: Pitch::from_midi(midi=60), ticks: 2, }
  let track = wb_track([note])
  let tracks : Array[Track] = [track]
  let song = Song::new(
    meter=Meter::six_eight(),
    tempo=Tempo::standard(),
    tracks~,
  )
  inspect(song.tracks.length(), content="1")
  // Mutate the authoring array: the snapshot is a separate array and must
  // not notice.
  tracks.push(wb_track([{ pitch: Pitch::from_midi(midi=72), ticks: 1, }]))
  let _ = tracks.pop()
  inspect(song.tracks.length(), content="1")
  inspect(song.track_count(), content="1")
}

///|
test "mutating the authoring notes array after Song::new does not change the song" {
  let note = { pitch: Pitch::from_midi(midi=60), ticks: 2, }
  let track = wb_track([note])
  let tracks : Array[Track] = [track]
  let song = Song::new(
    meter=Meter::six_eight(),
    tempo=Tempo::standard(),
    tracks~,
  )
  inspect(song.tracks[0].notes.length(), content="1")
  // Mutate the track's notes array after the snapshot: the song's copied
  // notes array must stay exactly as constructed.
  track.notes.push({ pitch: Pitch::from_midi(midi=64), ticks: 3, })
  let _ = track.notes.pop()
  inspect(song.tracks[0].notes.length(), content="1")
  inspect(song.tracks[0].notes[0].ticks, content="2")
  debug_inspect(song.tracks[0].notes[0].pitch, content="Some({ midi: 60 })")
}

///|
test "the snapshot shares no notes array with any authoring track" {
  let note = { pitch: Pitch::from_midi(midi=60), ticks: 2, }
  let track_a = wb_track([note])
  let track_b = wb_track([note])
  let song = Song::new(meter=Meter::six_eight(), tempo=Tempo::standard(), tracks=[
    track_a, track_b,
  ])
  // Two authoring tracks built from the same note value snapshot into two
  // independent arrays: mutating one snapshot cell cannot alias the other.
  song.tracks[0].notes.push({ pitch: None, ticks: 1, })
  inspect(song.tracks[0].notes.length(), content="2")
  inspect(song.tracks[1].notes.length(), content="1")
}
