///|
test "Pitch::from_midi accepts MIDI range boundaries" {
  debug_inspect(@music.Pitch::from_midi(midi=0), content="Some({ midi: 0 })")
  debug_inspect(
    @music.Pitch::from_midi(midi=127),
    content="Some({ midi: 127 })",
  )
}

///|
test "Pitch::from_midi rejects out-of-range numbers" {
  debug_inspect(@music.Pitch::from_midi(midi=-1), content="None")
  debug_inspect(@music.Pitch::from_midi(midi=128), content="None")
}
