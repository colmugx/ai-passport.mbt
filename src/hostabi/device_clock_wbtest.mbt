///|
/// Host probes into the native test stub's frozen clocks (see
/// native_stub.c): drive the availability fact, the playback position and
/// the frame clock exactly as the device firmware reports them.
extern "c" fn test_set_music_available(available : Int) -> Unit = "ai_passport_test_set_music_available"

///|
extern "c" fn test_set_music_position(position_us : Int64) -> Unit = "ai_passport_test_set_music_position"

///|
extern "c" fn test_set_now_us(now_us : Int64) -> Unit = "ai_passport_test_set_now_us"

///|
test "the device frame clock reports the stub timeline" {
  test_set_now_us(1_500_000L)
  assert_eq(device_now_us(), 1_500_000L)
  test_set_now_us(2_000_000L)
  assert_eq(device_now_us(), 2_000_000L)
  // Restore the shared stub state for other tests.
  test_set_now_us(0L)
}

///|
test "transport availability decides the playback Option" {
  // Unavailable transport: None, whatever raw position value sits in the
  // stub — the position never infers availability.
  test_set_music_available(0)
  test_set_music_position(123_456L)
  assert_eq(device_playback_position_us(), None)
  // Live transport: the raw position crosses as Some, and exactly 0 — the
  // track start and the PCM loop boundary — is live playback, never the
  // unavailable state.
  test_set_music_available(1)
  test_set_music_position(0L)
  assert_eq(device_playback_position_us(), Some(0L))
  test_set_music_position(600_000L)
  assert_eq(device_playback_position_us(), Some(600_000L))
  // Restore the shared stub state for other tests.
  test_set_music_available(0)
  test_set_music_position(0L)
}
