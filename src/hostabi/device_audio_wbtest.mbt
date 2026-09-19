///|
/// Host probes into the native test stub's recording of the absolute audio
/// output facts the mirror wrote (see native_stub.c).
extern "c" fn test_last_output_volume() -> Int = "ai_passport_test_last_output_volume"

///|
extern "c" fn test_last_output_muted() -> Int = "ai_passport_test_last_output_muted"

///|
extern "c" fn test_output_set_calls() -> Int = "ai_passport_test_output_set_calls"

///|
test "a fresh mirror starts silent and repeats of the seeded facts never write" {
  let before = test_output_set_calls()
  let mirror = DeviceAudioMirror(initial_volume=80, initial_muted=false)
  // Creating the mirror and re-syncing the exact facts it was seeded with
  // crosses nothing: identical state never reaches the transport.
  mirror.sync(80, muted=false)
  assert_eq(test_output_set_calls(), before)
  assert_eq(mirror.applied_volume, 80)
  assert_eq(mirror.applied_muted, false)
}

///|
test "a volume change writes once with the C integer encoding" {
  let mirror = DeviceAudioMirror(initial_volume=80, initial_muted=false)
  let before = test_output_set_calls()
  mirror.sync(90, muted=false)
  assert_eq(test_output_set_calls(), before + 1)
  assert_eq(test_last_output_volume(), 90)
  assert_eq(test_last_output_muted(), 0)
  // Repeating the now-applied state writes nothing.
  mirror.sync(90, muted=false)
  assert_eq(test_output_set_calls(), before + 1)
}

///|
test "a mute-only change writes once and keeps the remembered volume" {
  let mirror = DeviceAudioMirror(initial_volume=80, initial_muted=false)
  let before = test_output_set_calls()
  mirror.sync(80, muted=true)
  assert_eq(test_output_set_calls(), before + 1)
  assert_eq(test_last_output_volume(), 80)
  assert_eq(test_last_output_muted(), 1)
  // Unmuting restores the audible state without re-sending a volume.
  mirror.sync(80, muted=false)
  assert_eq(test_output_set_calls(), before + 2)
  assert_eq(test_last_output_muted(), 0)
  assert_eq(test_last_output_volume(), 80)
}

///|
test "volume and mute travel together as one coherent snapshot" {
  let mirror = DeviceAudioMirror(initial_volume=80, initial_muted=false)
  let before = test_output_set_calls()
  mirror.sync(100, muted=true)
  // One call carries both absolute facts; neither is applied alone.
  assert_eq(test_output_set_calls(), before + 1)
  assert_eq(test_last_output_volume(), 100)
  assert_eq(test_last_output_muted(), 1)
}
