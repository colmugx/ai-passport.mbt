///|
test "State::new starts standing still, unpaused and with a four-voice 6/8 song" {
  let state = State::new()
  inspect(state.speed().level, content="0")
  inspect(state.paused(), content="false")
  inspect(state.frame(), content="0")
  inspect(state.scroll(), content="0")
  inspect(state.walker_frame(), content="0")
  let song = state.song()
  inspect(song.tracks.length(), content="4")
  inspect(song.meter.numerator, content="6")
  inspect(song.meter.denominator, content="8")
}

///|
test "Speed::zero is the standing-still level" {
  inspect(Speed::zero().level, content="0")
}

///|
test "showcase song uses the four documented roles, each with a rest" {
  let song = State::new().song()
  debug_inspect(song.tracks[0].instrument.waveform, content="Pulse12")
  debug_inspect(song.tracks[1].instrument.waveform, content="Pulse25")
  debug_inspect(song.tracks[2].instrument.waveform, content="Pulse50")
  debug_inspect(song.tracks[3].instrument.waveform, content="Triangle")
  for track in song.tracks {
    assert_true(track.notes.length() >= 1)
    let mut has_rest = false
    for n in track.notes {
      if n.pitch is None {
        has_rest = true
      }
    }
    assert_true(has_rest)
  }
}
