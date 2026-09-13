///|
/// Builds a one-instrument track for sequencer tests. The instrument literal
/// is minimal — the sequencer only forwards it, the synth never sees it here.
fn seq_track(
  name : String,
  waveform : @music.Waveform,
  notes : Array[@music.Note],
) -> @music.Track {
  {
    instrument: {
      name,
      waveform,
      envelope: { attack_ms: 0, decay_ms: 1, sustain: 0, release_ms: 1, },
      volume: 0,
      vibrato: None,
    },
    notes,
  }
}

///|
/// Compact summary of a step's events. NoteOn embeds a full `Instrument`,
/// so whole-event snapshots would be enormous; this keeps the assertions on
/// the fields the sequencer owns (track, pitch, tick-gate length, waveform)
/// while the instrument itself is asserted separately.
fn summarize(events : Array[@music.NoteOn]) -> String {
  let buf = StringBuilder()
  buf.write_string("[")
  for i, ev in events {
    if i > 0 {
      buf.write_string(", ")
    }
    let wf = match ev.instrument.waveform {
      @music.Pulse12 => "Pulse12"
      @music.Pulse25 => "Pulse25"
      @music.Pulse50 => "Pulse50"
      @music.Triangle => "Triangle"
      @music.Noise => "Noise"
    }
    buf.write_string("t\{ev.track} m\{ev.pitch.midi} k\{ev.ticks} \{wf}")
  }
  buf.write_string("]")
  buf.to_string()
}

///|
test "sequencer delivers note starts across a full default loop" {
  let track = seq_track("Celesta", @music.Pulse12, [
    { pitch: @music.Pitch::from_midi(midi=60), ticks: 2, },
    { pitch: None, ticks: 1, },
    { pitch: @music.Pitch::from_midi(midi=64), ticks: 3, },
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
  inspect(summarize(seq.step()), content="[t0 m60 k2 Pulse12]")
  inspect(seq.tick(), content="1")
  debug_inspect(seq.step(), content="[]")
  inspect(seq.tick(), content="2")
  // Tick 2: the rest starts and is skipped silently.
  debug_inspect(seq.step(), content="[]")
  inspect(seq.tick(), content="3")
  // Tick 3: E4 starts.
  inspect(summarize(seq.step()), content="[t0 m64 k3 Pulse12]")
  inspect(seq.tick(), content="4")
  debug_inspect(seq.step(), content="[]")
  inspect(seq.tick(), content="5")
  // Tick 5 is the last tick; the next step wraps the transport to tick 0.
  debug_inspect(seq.step(), content="[]")
  inspect(seq.tick(), content="0")
  // First step of the wrapped cycle: C4 triggers again.
  inspect(summarize(seq.step()), content="[t0 m60 k2 Pulse12]")
  inspect(seq.tick(), content="1")
}

///|
test "multi-track events are ordered by track index and outlive short tracks" {
  let celesta = seq_track("Celesta", @music.Pulse12, [
    { pitch: @music.Pitch::from_midi(midi=60), ticks: 2, },
  ])
  let woodwind = seq_track("Woodwind Lead", @music.Pulse25, [
    { pitch: @music.Pitch::from_midi(midi=64), ticks: 3, },
    { pitch: None, ticks: 1, },
    { pitch: @music.Pitch::from_midi(midi=67), ticks: 2, },
  ])
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[celesta, woodwind],
  )
  let seq = @music.Sequencer::new(song~)
  inspect(seq.length(), content="6")
  // Both tracks start at tick 0; the shorter track is reported first.
  inspect(
    summarize(seq.step()),
    content="[t0 m60 k2 Pulse12, t1 m64 k3 Pulse25]",
  )
  inspect(seq.tick(), content="1")
  // The two-tick Celesta track goes silent for the rest of the loop while the
  // six-tick Woodwind track continues through its rest to G4.
  debug_inspect(seq.step(), content="[]")
  debug_inspect(seq.step(), content="[]")
  debug_inspect(seq.step(), content="[]")
  inspect(summarize(seq.step()), content="[t1 m67 k2 Pulse25]")
  inspect(seq.tick(), content="5")
  debug_inspect(seq.step(), content="[]")
  inspect(seq.tick(), content="0")
  // After the wrap both tracks resume from tick 0.
  inspect(
    summarize(seq.step()),
    content="[t0 m60 k2 Pulse12, t1 m64 k3 Pulse25]",
  )
  inspect(seq.tick(), content="1")
}

///|
test "four tracks build via Song::new and all trigger at tick 0" {
  let tracks = [
    seq_track("Celesta", @music.Pulse12, [
      { pitch: @music.Pitch::from_midi(midi=72), ticks: 1, },
    ]),
    seq_track("Woodwind Lead", @music.Pulse25, [
      { pitch: @music.Pitch::from_midi(midi=64), ticks: 2, },
    ]),
    seq_track("Lyrical Strings", @music.Pulse50, [
      { pitch: @music.Pitch::from_midi(midi=57), ticks: 3, },
    ]),
    seq_track("Low Strings", @music.Triangle, [
      { pitch: @music.Pitch::from_midi(midi=36), ticks: 6, },
    ]),
  ]
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks~,
  )
  let seq = @music.Sequencer::new(song~)
  inspect(seq.length(), content="6")
  inspect(
    summarize(seq.step()),
    content="[t0 m72 k1 Pulse12, t1 m64 k2 Pulse25, t2 m57 k3 Pulse50, t3 m36 k6 Triangle]",
  )
  inspect(seq.tick(), content="1")
  debug_inspect(seq.step(), content="[]")
  debug_inspect(seq.step(), content="[]")
  debug_inspect(seq.step(), content="[]")
  debug_inspect(seq.step(), content="[]")
  debug_inspect(seq.step(), content="[]")
  inspect(seq.tick(), content="0")
  inspect(
    summarize(seq.step()),
    content="[t0 m72 k1 Pulse12, t1 m64 k2 Pulse25, t2 m57 k3 Pulse50, t3 m36 k6 Triangle]",
  )
}

///|
test "loop region retriggers at the start and never repeats earlier events" {
  let woodwind = seq_track("Woodwind Lead", @music.Pulse25, [
    { pitch: @music.Pitch::from_midi(midi=69), ticks: 2, },
    { pitch: @music.Pitch::from_midi(midi=71), ticks: 2, },
    { pitch: @music.Pitch::from_midi(midi=72), ticks: 2, },
  ])
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[woodwind],
  )
  let seq = @music.Sequencer::new_with_loop(song~, start=2, end=4)
  inspect(seq.length(), content="4")
  // First pass plays the pre-loop region once: A4 starts at tick 0.
  inspect(summarize(seq.step()), content="[t0 m69 k2 Pulse25]")
  inspect(seq.tick(), content="1")
  debug_inspect(seq.step(), content="[]")
  inspect(seq.tick(), content="2")
  // B4 starts exactly at loop_start.
  inspect(summarize(seq.step()), content="[t0 m71 k2 Pulse25]")
  inspect(seq.tick(), content="3")
  // The transport wraps back to loop_start=2; tick() stays inside [0, 4).
  debug_inspect(seq.step(), content="[]")
  inspect(seq.tick(), content="2")
  // Triggering resumes at loop_start; A4 (before the start) never repeats and
  // C5 (at the loop end) is never reached.
  inspect(summarize(seq.step()), content="[t0 m71 k2 Pulse25]")
  inspect(seq.tick(), content="3")
  debug_inspect(seq.step(), content="[]")
  inspect(seq.tick(), content="2")
  inspect(summarize(seq.step()), content="[t0 m71 k2 Pulse25]")
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
    { pitch: @music.Pitch::from_midi(midi=60), ticks: 2, },
    { pitch: @music.Pitch::from_midi(midi=64), ticks: 3, },
  ])
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[strings],
  )
  let seq = @music.Sequencer::new_with_loop(song~, start=0, end=3)
  inspect(seq.length(), content="3")
  inspect(summarize(seq.step()), content="[t0 m60 k2 Pulse50]")
  debug_inspect(seq.step(), content="[]")
  // E4 starts at tick 2 (end - 1) and its three-tick gate crosses the loop
  // end; it triggers on this wrap step and is not retriggered while sounding.
  inspect(summarize(seq.step()), content="[t0 m64 k3 Pulse50]")
  inspect(seq.tick(), content="0")
  inspect(summarize(seq.step()), content="[t0 m60 k2 Pulse50]")
  debug_inspect(seq.step(), content="[]")
  // Next cycle: E4 triggers exactly once again.
  inspect(summarize(seq.step()), content="[t0 m64 k3 Pulse50]")
  inspect(seq.tick(), content="0")
}

///|
test "track index, gate length and instrument propagate from the track" {
  let bass = seq_track("Low Strings", @music.Triangle, [
    { pitch: @music.Pitch::from_midi(midi=48), ticks: 1, },
  ])
  let strings = seq_track("Lyrical Strings", @music.Pulse50, [
    { pitch: @music.Pitch::from_midi(midi=55), ticks: 2, },
  ])
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[bass, strings],
  )
  let seq = @music.Sequencer::new(song~)
  inspect(seq.song().tracks.length(), content="2")
  let events = seq.step()
  inspect(summarize(events), content="[t0 m48 k1 Triangle, t1 m55 k2 Pulse50]")
  // The NoteOn carries the track's whole instrument, envelope included.
  inspect(events[1].instrument.name, content="Lyrical Strings")
  inspect(events[1].instrument.envelope.attack_ms, content="0")
}

///|
test "panic Sequencer::new_with_loop rejects a negative start" {
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[
      seq_track("Celesta", @music.Pulse12, [
        { pitch: @music.Pitch::from_midi(midi=60), ticks: 6, },
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
        { pitch: @music.Pitch::from_midi(midi=60), ticks: 6, },
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
        { pitch: @music.Pitch::from_midi(midi=60), ticks: 6, },
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
        { pitch: @music.Pitch::from_midi(midi=60), ticks: 0, },
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
        { pitch: @music.Pitch::from_midi(midi=60), ticks: -1, },
      ]),
    ],
  )
  ignore(@music.Sequencer::new_with_loop(song~, start=0, end=6))
}
