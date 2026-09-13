///|
test "a rest note constructs with pitch None" {
  let rest : @music.Note = { pitch: None, ticks: 12, }
  debug_inspect(rest, content="{ pitch: None, ticks: 12 }")
  let sounding : @music.Note = {
    pitch: @music.Pitch::from_midi(midi=64),
    ticks: 4,
  }
  debug_inspect(sounding, content="{ pitch: Some({ midi: 64 }), ticks: 4 }")
}
