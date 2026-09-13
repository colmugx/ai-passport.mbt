///|
/// Builds a one-instrument track for sequencer tests.
fn seq_track(
  name : String,
  waveform : @music.Waveform,
  notes : Array[@music.Note],
) -> @music.Track {
  { instrument: { name, waveform, }, notes, }
}

///|
test "sequencer delivers note starts across a full default loop" {
  let track = seq_track("Celesta", @music.Pulse12, [
    { pitch: @music.Pitch::from_midi(midi=60), eighths: 2, },
    { pitch: None, eighths: 1, },
    { pitch: @music.Pitch::from_midi(midi=64), eighths: 3, },
  ])
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[track],
  )
  let seq = @music.Sequencer::new(song~)
  inspect(seq.length(), content="6")
  inspect(seq.tick(), content="0")
  // Tick 0: C4 starts (reported by the first step, after which tick() == 1).
  debug_inspect(
    seq.step(),
    content="[{ track: 0, pitch: { midi: 60 }, eighths: 2, waveform: Pulse12 }]",
  )
  inspect(seq.tick(), content="1")
  debug_inspect(seq.step(), content="[]")
  inspect(seq.tick(), content="2")
  // Tick 2: the rest starts and is skipped silently.
  debug_inspect(seq.step(), content="[]")
  inspect(seq.tick(), content="3")
  // Tick 3: E4 starts.
  debug_inspect(
    seq.step(),
    content="[{ track: 0, pitch: { midi: 64 }, eighths: 3, waveform: Pulse12 }]",
  )
  inspect(seq.tick(), content="4")
  debug_inspect(seq.step(), content="[]")
  inspect(seq.tick(), content="5")
  // Tick 5 is the last tick; the next step wraps the transport to tick 0.
  debug_inspect(seq.step(), content="[]")
  inspect(seq.tick(), content="0")
  // First step of the wrapped cycle: C4 triggers again.
  debug_inspect(
    seq.step(),
    content="[{ track: 0, pitch: { midi: 60 }, eighths: 2, waveform: Pulse12 }]",
  )
  inspect(seq.tick(), content="1")
}

///|
test "multi-track events are ordered by track index and outlive short tracks" {
  let celesta = seq_track("Celesta", @music.Pulse12, [
    { pitch: @music.Pitch::from_midi(midi=60), eighths: 2, },
  ])
  let woodwind = seq_track("Woodwind Lead", @music.Pulse25, [
    { pitch: @music.Pitch::from_midi(midi=64), eighths: 3, },
    { pitch: None, eighths: 1, },
    { pitch: @music.Pitch::from_midi(midi=67), eighths: 2, },
  ])
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[celesta, woodwind],
  )
  let seq = @music.Sequencer::new(song~)
  inspect(seq.length(), content="6")
  // Both tracks start at tick 0; the shorter track is reported first.
  debug_inspect(
    seq.step(),
    content=(
      #|[
      #|  { track: 0, pitch: { midi: 60 }, eighths: 2, waveform: Pulse12 },
      #|  { track: 1, pitch: { midi: 64 }, eighths: 3, waveform: Pulse25 },
      #|]
    ),
  )
  inspect(seq.tick(), content="1")
  // The two-tick Celesta track goes silent for the rest of the loop while the
  // six-tick Woodwind track continues through its rest to G4.
  debug_inspect(seq.step(), content="[]")
  debug_inspect(seq.step(), content="[]")
  debug_inspect(seq.step(), content="[]")
  debug_inspect(
    seq.step(),
    content="[{ track: 1, pitch: { midi: 67 }, eighths: 2, waveform: Pulse25 }]",
  )
  inspect(seq.tick(), content="5")
  debug_inspect(seq.step(), content="[]")
  inspect(seq.tick(), content="0")
  // After the wrap both tracks resume from tick 0.
  debug_inspect(
    seq.step(),
    content=(
      #|[
      #|  { track: 0, pitch: { midi: 60 }, eighths: 2, waveform: Pulse12 },
      #|  { track: 1, pitch: { midi: 64 }, eighths: 3, waveform: Pulse25 },
      #|]
    ),
  )
  inspect(seq.tick(), content="1")
}

///|
test "four tracks build via Song::new and all trigger at tick 0" {
  let tracks = [
    seq_track("Celesta", @music.Pulse12, [
      { pitch: @music.Pitch::from_midi(midi=72), eighths: 1, },
    ]),
    seq_track("Woodwind Lead", @music.Pulse25, [
      { pitch: @music.Pitch::from_midi(midi=64), eighths: 2, },
    ]),
    seq_track("Lyrical Strings", @music.Pulse50, [
      { pitch: @music.Pitch::from_midi(midi=57), eighths: 3, },
    ]),
    seq_track("Low Strings", @music.Triangle, [
      { pitch: @music.Pitch::from_midi(midi=36), eighths: 6, },
    ]),
  ]
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks~,
  )
  let seq = @music.Sequencer::new(song~)
  inspect(seq.length(), content="6")
  debug_inspect(
    seq.step(),
    content=(
      #|[
      #|  { track: 0, pitch: { midi: 72 }, eighths: 1, waveform: Pulse12 },
      #|  { track: 1, pitch: { midi: 64 }, eighths: 2, waveform: Pulse25 },
      #|  { track: 2, pitch: { midi: 57 }, eighths: 3, waveform: Pulse50 },
      #|  { track: 3, pitch: { midi: 36 }, eighths: 6, waveform: Triangle },
      #|]
    ),
  )
  inspect(seq.tick(), content="1")
  debug_inspect(seq.step(), content="[]")
  debug_inspect(seq.step(), content="[]")
  debug_inspect(seq.step(), content="[]")
  debug_inspect(seq.step(), content="[]")
  debug_inspect(seq.step(), content="[]")
  inspect(seq.tick(), content="0")
  debug_inspect(
    seq.step(),
    content=(
      #|[
      #|  { track: 0, pitch: { midi: 72 }, eighths: 1, waveform: Pulse12 },
      #|  { track: 1, pitch: { midi: 64 }, eighths: 2, waveform: Pulse25 },
      #|  { track: 2, pitch: { midi: 57 }, eighths: 3, waveform: Pulse50 },
      #|  { track: 3, pitch: { midi: 36 }, eighths: 6, waveform: Triangle },
      #|]
    ),
  )
}

///|
test "loop region retriggers at the start and never repeats earlier events" {
  let woodwind = seq_track("Woodwind Lead", @music.Pulse25, [
    { pitch: @music.Pitch::from_midi(midi=69), eighths: 2, },
    { pitch: @music.Pitch::from_midi(midi=71), eighths: 2, },
    { pitch: @music.Pitch::from_midi(midi=72), eighths: 2, },
  ])
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[woodwind],
  )
  let seq = @music.Sequencer::new_with_loop(song~, start=2, end=4)
  inspect(seq.length(), content="4")
  // First pass plays the pre-loop region once: A4 starts at tick 0.
  debug_inspect(
    seq.step(),
    content="[{ track: 0, pitch: { midi: 69 }, eighths: 2, waveform: Pulse25 }]",
  )
  inspect(seq.tick(), content="1")
  debug_inspect(seq.step(), content="[]")
  inspect(seq.tick(), content="2")
  // B4 starts exactly at loop_start.
  debug_inspect(
    seq.step(),
    content="[{ track: 0, pitch: { midi: 71 }, eighths: 2, waveform: Pulse25 }]",
  )
  inspect(seq.tick(), content="3")
  // The transport wraps back to loop_start=2; tick() stays inside [0, 4).
  debug_inspect(seq.step(), content="[]")
  inspect(seq.tick(), content="2")
  // Triggering resumes at loop_start; A4 (before the start) never repeats and
  // C5 (at the loop end) is never reached.
  debug_inspect(
    seq.step(),
    content="[{ track: 0, pitch: { midi: 71 }, eighths: 2, waveform: Pulse25 }]",
  )
  inspect(seq.tick(), content="3")
  debug_inspect(seq.step(), content="[]")
  inspect(seq.tick(), content="2")
  debug_inspect(
    seq.step(),
    content="[{ track: 0, pitch: { midi: 71 }, eighths: 2, waveform: Pulse25 }]",
  )
  inspect(seq.tick(), content="3")
}

///|
test "empty song is permanently idle" {
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[],
  )
  let seq = @music.Sequencer::new(song~)
  inspect(seq.length(), content="0")
  inspect(seq.tick(), content="0")
  debug_inspect(seq.step(), content="[]")
  debug_inspect(seq.step(), content="[]")
  debug_inspect(seq.step(), content="[]")
  inspect(seq.tick(), content="0")
}

///|
test "a note crossing the loop end finishes and triggers once per cycle" {
  let strings = seq_track("Lyrical Strings", @music.Pulse50, [
    { pitch: @music.Pitch::from_midi(midi=60), eighths: 2, },
    { pitch: @music.Pitch::from_midi(midi=64), eighths: 3, },
  ])
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[strings],
  )
  let seq = @music.Sequencer::new_with_loop(song~, start=0, end=3)
  inspect(seq.length(), content="3")
  debug_inspect(
    seq.step(),
    content="[{ track: 0, pitch: { midi: 60 }, eighths: 2, waveform: Pulse50 }]",
  )
  debug_inspect(seq.step(), content="[]")
  // E4 starts at tick 2 (end - 1) and its three-tick gate crosses the loop
  // end; it triggers on this wrap step and is not retriggered while sounding.
  debug_inspect(
    seq.step(),
    content="[{ track: 0, pitch: { midi: 64 }, eighths: 3, waveform: Pulse50 }]",
  )
  inspect(seq.tick(), content="0")
  debug_inspect(
    seq.step(),
    content="[{ track: 0, pitch: { midi: 60 }, eighths: 2, waveform: Pulse50 }]",
  )
  debug_inspect(seq.step(), content="[]")
  // Next cycle: E4 triggers exactly once again.
  debug_inspect(
    seq.step(),
    content="[{ track: 0, pitch: { midi: 64 }, eighths: 3, waveform: Pulse50 }]",
  )
  inspect(seq.tick(), content="0")
}

///|
test "track index, gate length and waveform propagate from the instrument" {
  let bass = seq_track("Low Strings", @music.Triangle, [
    { pitch: @music.Pitch::from_midi(midi=48), eighths: 1, },
  ])
  let strings = seq_track("Lyrical Strings", @music.Pulse50, [
    { pitch: @music.Pitch::from_midi(midi=55), eighths: 2, },
  ])
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[bass, strings],
  )
  let seq = @music.Sequencer::new(song~)
  inspect(seq.song().tracks.length(), content="2")
  debug_inspect(
    seq.step(),
    content=(
      #|[
      #|  { track: 0, pitch: { midi: 48 }, eighths: 1, waveform: Triangle },
      #|  { track: 1, pitch: { midi: 55 }, eighths: 2, waveform: Pulse50 },
      #|]
    ),
  )
}

///|
test "panic Sequencer::new_with_loop rejects a negative start" {
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[
      seq_track("Celesta", @music.Pulse12, [
        { pitch: @music.Pitch::from_midi(midi=60), eighths: 6, },
      ]),
    ],
  )
  ignore(@music.Sequencer::new_with_loop(song~, start=-1, end=4))
}

///|
test "panic Sequencer::new_with_loop rejects an empty range" {
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[
      seq_track("Celesta", @music.Pulse12, [
        { pitch: @music.Pitch::from_midi(midi=60), eighths: 6, },
      ]),
    ],
  )
  ignore(@music.Sequencer::new_with_loop(song~, start=3, end=3))
}

///|
test "panic Sequencer::new_with_loop rejects an end past the song" {
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[
      seq_track("Celesta", @music.Pulse12, [
        { pitch: @music.Pitch::from_midi(midi=60), eighths: 6, },
      ]),
    ],
  )
  // Documented choice: end beyond the song length aborts rather than clamps.
  ignore(@music.Sequencer::new_with_loop(song~, start=0, end=7))
}

///|
test "panic Sequencer::new rejects a zero-length note" {
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[
      seq_track("Celesta", @music.Pulse12, [
        { pitch: @music.Pitch::from_midi(midi=60), eighths: 0, },
      ]),
    ],
  )
  ignore(@music.Sequencer::new(song~))
}

///|
test "panic Sequencer::new_with_loop rejects a negative-length note" {
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[
      seq_track("Celesta", @music.Pulse12, [
        { pitch: @music.Pitch::from_midi(midi=60), eighths: -1, },
      ]),
    ],
  )
  ignore(@music.Sequencer::new_with_loop(song~, start=0, end=6))
}
