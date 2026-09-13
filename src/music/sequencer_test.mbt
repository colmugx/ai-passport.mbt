// Black-box tests for the arrival-based transport: the first step() is the
// arrival at tick 0, later steps report note-starts landing on the tick the
// transport moves onto (including wrapped arrivals at loop_start), and
// step_into delivers them through a caller-owned buffer without allocation.

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
/// Steps the sequencer through the realtime path — a scratch buffer sized to
/// the song's track count — and summarizes what landed in it.
fn step_summary(seq : @music.Sequencer) -> String {
  let buf : FixedArray[@music.NoteOn?] = FixedArray::make(
    seq.song().tracks.length(),
    None,
  )
  let count = seq.step_into(buf)
  let out = StringBuilder()
  out.write_string("[")
  for i in 0..<count {
    if i > 0 {
      out.write_string(", ")
    }
    let ev = buf[i].unwrap()
    let wf = match ev.instrument.waveform {
      @music.Pulse12 => "Pulse12"
      @music.Pulse25 => "Pulse25"
      @music.Pulse50 => "Pulse50"
      @music.Triangle => "Triangle"
      @music.Noise => "Noise"
    }
    out.write_string("t\{ev.track} m\{ev.pitch.midi} k\{ev.ticks} \{wf}")
  }
  out.write_string("]")
  out.to_string()
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
  // The first step is the arrival at tick 0: C4 fires before any transport
  // time has elapsed, and the position stays on tick 0.
  inspect(step_summary(seq), content="[t0 m60 k2 Pulse12]")
  inspect(seq.tick(), content="0")
  inspect(step_summary(seq), content="[]")
  inspect(seq.tick(), content="1")
  // Tick 2: the rest starts and is skipped silently.
  inspect(step_summary(seq), content="[]")
  inspect(seq.tick(), content="2")
  // Tick 3: E4 starts.
  inspect(step_summary(seq), content="[t0 m64 k3 Pulse12]")
  inspect(seq.tick(), content="3")
  inspect(step_summary(seq), content="[]")
  inspect(seq.tick(), content="4")
  // Tick 5 is the last arrival inside the loop; the next step wraps the
  // transport back to tick 0 and fires C4 on the wrapped arrival itself.
  inspect(step_summary(seq), content="[]")
  inspect(seq.tick(), content="5")
  inspect(step_summary(seq), content="[t0 m60 k2 Pulse12]")
  inspect(seq.tick(), content="0")
  inspect(step_summary(seq), content="[]")
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
  // Both tracks start at tick 0 and fire together on the first arrival; the
  // shorter track is reported first.
  inspect(step_summary(seq), content="[t0 m60 k2 Pulse12, t1 m64 k3 Pulse25]")
  inspect(seq.tick(), content="0")
  // The two-tick Celesta track goes silent for the rest of the loop while the
  // six-tick Woodwind track continues through its rest to G4 at tick 4.
  inspect(step_summary(seq), content="[]")
  inspect(step_summary(seq), content="[]")
  inspect(step_summary(seq), content="[]")
  inspect(step_summary(seq), content="[t1 m67 k2 Pulse25]")
  inspect(seq.tick(), content="4")
  inspect(step_summary(seq), content="[]")
  inspect(seq.tick(), content="5")
  // The wrap re-fires both tick-0 starts on the wrapped arrival.
  inspect(step_summary(seq), content="[t0 m60 k2 Pulse12, t1 m64 k3 Pulse25]")
  inspect(seq.tick(), content="0")
  inspect(step_summary(seq), content="[]")
  inspect(seq.tick(), content="1")
}

///|
test "step_into delivers four simultaneous events in per-track slots" {
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
  // Pre-fill every slot — including two surplus slots — with junk, so the
  // step must overwrite slots 0..3 and reset the surplus to None.
  let junk : @music.NoteOn = {
    track: 9,
    pitch: @music.Pitch::from_midi(midi=60).unwrap(),
    ticks: 9,
    instrument: tracks[0].instrument,
  }
  let buf : FixedArray[@music.NoteOn?] = FixedArray::make(6, Some(junk))
  let count = seq.step_into(buf)
  inspect(count, content="4")
  // All four simultaneous events, ordered by track index.
  inspect(buf[0].unwrap().track, content="0")
  inspect(buf[0].unwrap().pitch.midi, content="72")
  inspect(buf[1].unwrap().track, content="1")
  inspect(buf[1].unwrap().pitch.midi, content="64")
  inspect(buf[2].unwrap().track, content="2")
  inspect(buf[2].unwrap().pitch.midi, content="57")
  inspect(buf[3].unwrap().track, content="3")
  inspect(buf[3].unwrap().pitch.midi, content="36")
  // Surplus slots are cleared, never left stale.
  inspect(buf[4] is None, content="true")
  inspect(buf[5] is None, content="true")
  // A later step with no events leaves the whole buffer cleared.
  let _ = seq.step_into(buf)
  let mut stale = false
  for i in 0..<6 {
    if buf[i] is Some(_) {
      stale = true
    }
  }
  inspect(stale, content="false")
}

///|
test "the allocating step() agrees with step_into on the same transport" {
  let track = seq_track("Celesta", @music.Pulse12, [
    { pitch: @music.Pitch::from_midi(midi=60), ticks: 2, },
    { pitch: @music.Pitch::from_midi(midi=64), ticks: 2, },
  ])
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[track],
  )
  let seq = @music.Sequencer::new(song~)
  inspect(summarize(seq.step()), content="[t0 m60 k2 Pulse12]")
  inspect(seq.tick(), content="0")
  inspect(summarize(seq.step()), content="[]")
  inspect(seq.tick(), content="1")
  inspect(summarize(seq.step()), content="[t0 m64 k2 Pulse12]")
  inspect(seq.tick(), content="2")
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
  inspect(step_summary(seq), content="[t0 m69 k2 Pulse25]")
  inspect(seq.tick(), content="0")
  inspect(step_summary(seq), content="[]")
  inspect(seq.tick(), content="1")
  // B4 starts exactly at loop_start.
  inspect(step_summary(seq), content="[t0 m71 k2 Pulse25]")
  inspect(seq.tick(), content="2")
  inspect(step_summary(seq), content="[]")
  inspect(seq.tick(), content="3")
  // The wrap lands back on loop_start=2 and the wrapped arrival fires B4
  // again; tick() stays inside [0, 4).
  inspect(step_summary(seq), content="[t0 m71 k2 Pulse25]")
  inspect(seq.tick(), content="2")
  inspect(step_summary(seq), content="[]")
  inspect(seq.tick(), content="3")
  inspect(step_summary(seq), content="[t0 m71 k2 Pulse25]")
  inspect(seq.tick(), content="2")
}

///|
test "a mid-note loop start never retriggers the note it lands inside" {
  let strings = seq_track("Lyrical Strings", @music.Pulse50, [
    { pitch: @music.Pitch::from_midi(midi=60), ticks: 4, },
    { pitch: @music.Pitch::from_midi(midi=64), ticks: 2, },
  ])
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[strings],
  )
  // The loop starts two ticks into the four-tick C4.
  let seq = @music.Sequencer::new_with_loop(song~, start=2, end=6)
  inspect(seq.length(), content="6")
  inspect(step_summary(seq), content="[t0 m60 k4 Pulse50]")
  inspect(seq.tick(), content="0")
  inspect(step_summary(seq), content="[]")
  inspect(seq.tick(), content="1")
  // Ticks 2 and 3 are mid-note: C4 keeps sounding, nothing fires.
  inspect(step_summary(seq), content="[]")
  inspect(seq.tick(), content="2")
  inspect(step_summary(seq), content="[]")
  inspect(seq.tick(), content="3")
  inspect(step_summary(seq), content="[t0 m64 k2 Pulse50]")
  inspect(seq.tick(), content="4")
  inspect(step_summary(seq), content="[]")
  inspect(seq.tick(), content="5")
  // The wrapped arrival lands mid-note on C4 (two ticks consumed): silent.
  inspect(step_summary(seq), content="[]")
  inspect(seq.tick(), content="2")
  inspect(step_summary(seq), content="[]")
  inspect(seq.tick(), content="3")
  // E4 starts again at tick 4; C4 (before loop_start) never repeats.
  inspect(step_summary(seq), content="[t0 m64 k2 Pulse50]")
  inspect(seq.tick(), content="4")
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
  inspect(step_summary(seq), content="[t0 m60 k2 Pulse50]")
  inspect(seq.tick(), content="0")
  inspect(step_summary(seq), content="[]")
  inspect(seq.tick(), content="1")
  // E4 starts at tick 2 (end - 1) and its three-tick gate crosses the loop
  // end; it triggers on its own arrival and is not retriggered while sounding.
  inspect(step_summary(seq), content="[t0 m64 k3 Pulse50]")
  inspect(seq.tick(), content="2")
  // The wrap fires C4 again (the loop restarted); on the shared voice the
  // retrigger cuts E4's remaining gate.
  inspect(step_summary(seq), content="[t0 m60 k2 Pulse50]")
  inspect(seq.tick(), content="0")
  inspect(step_summary(seq), content="[]")
  inspect(seq.tick(), content="1")
  // Next cycle: E4 triggers exactly once again.
  inspect(step_summary(seq), content="[t0 m64 k3 Pulse50]")
  inspect(seq.tick(), content="2")
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
test "panic Sequencer::step_into rejects a buffer smaller than the track count" {
  let track = seq_track("Celesta", @music.Pulse12, [
    { pitch: @music.Pitch::from_midi(midi=60), ticks: 2, },
  ])
  let second = seq_track("Low Strings", @music.Triangle, [
    { pitch: @music.Pitch::from_midi(midi=48), ticks: 2, },
  ])
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[track, second],
  )
  let seq = @music.Sequencer::new(song~)
  // Two tracks can start two notes on one tick: one slot would silently
  // drop an event, so the contract aborts instead.
  let too_small : FixedArray[@music.NoteOn?] = FixedArray::make(1, None)
  ignore(seq.step_into(too_small))
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
