///|
test "a rest note constructs with pitch None" {
  let rest : @music.Note = { pitch: None, eighths: 3, }
  debug_inspect(rest, content="{ pitch: None, eighths: 3 }")
  let sounding : @music.Note = {
    pitch: @music.Pitch::from_midi(midi=64),
    eighths: 1,
  }
  debug_inspect(sounding, content="{ pitch: Some({ midi: 64 }), eighths: 1 }")
}
