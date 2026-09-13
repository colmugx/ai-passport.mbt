// Whitebox tests: these compile inside the audio package and may read the
// Player's private event scratch to pin the capacity invariant — the scratch
// is sized once from the Song snapshot's track count, and since a Song is an
// immutable deep copy, the two can never drift apart.

///|
test "player event scratch capacity matches the song snapshot's track count" {
  let notes : Array[@music.Note] = [
    { pitch: @music.Pitch::from_midi(midi=69), ticks: 4, },
  ]
  let tracks : Array[@music.Track] = [
    { instrument: @music.Instrument::celesta(), notes, },
    { instrument: @music.Instrument::woodwind(), notes, },
    { instrument: @music.Instrument::strings(), notes, },
  ]
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks~,
  ) catch {
    err => abort("test song violates four-voice cap: \{err}")
  }
  let player = Player::new(song~)
  inspect(player.events.length(), content="3")
  inspect(player.sequencer.song().track_count(), content="3")
  // The scratch is never resized and the snapshot never changes, so the
  // equality holds for the player's whole life.
  inspect(
    player.events.length() == player.sequencer.song().track_count(),
    content="true",
  )
}

///|
test "an empty song's scratch is empty and every arrival is a no-op" {
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[],
  ) catch {
    err => abort("empty song cannot raise: \{err}")
  }
  let player = Player::new(song~)
  inspect(player.events.length(), content="0")
  let out : FixedArray[Int] = FixedArray::make(3000, 7)
  player.render(out~)
  let mut nonzero = false
  for i in 0..<out.length() {
    if out[i] != 0 {
      nonzero = true
    }
  }
  inspect(nonzero, content="false")
}
