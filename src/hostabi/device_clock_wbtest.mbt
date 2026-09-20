///|
/// Host probe into the native test stub's frozen frame clock.
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
test "the obsolete frame-global playback position stays absent" {
  assert_eq(device_playback_position_us(), None)
}
