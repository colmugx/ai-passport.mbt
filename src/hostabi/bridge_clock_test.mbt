///|
test "the frame clock starts at zero and tracks frame time in milliseconds" {
  let bridge = @hostabi.HostBridge::new(store_u16=(_, _) => (), battery_percent=() => {
    -1
  })
  let clock : &@driver.Clock = bridge
  assert_eq(clock.monotonic_ms(), 0)
  bridge.advance(1500000L)
  assert_eq(clock.monotonic_ms(), 1500)
}

///|
test "equal or backwards frame timestamps never rewind the clock" {
  let bridge = @hostabi.HostBridge::new(store_u16=(_, _) => (), battery_percent=() => {
    -1
  })
  let clock : &@driver.Clock = bridge
  bridge.advance(2000000L)
  assert_eq(clock.monotonic_ms(), 2000)
  // Equal timestamp: holds, does not move.
  bridge.advance(2000000L)
  assert_eq(clock.monotonic_ms(), 2000)
  // Backwards timestamp: never rewinds.
  bridge.advance(1000000L)
  assert_eq(clock.monotonic_ms(), 2000)
}

///|
test "the clock stays monotonic across many frame advances" {
  let bridge = @hostabi.HostBridge::new(store_u16=(_, _) => (), battery_percent=() => {
    -1
  })
  let clock : &@driver.Clock = bridge
  // A host that jitters around an increasing timeline (60 us/frame step,
  // occasionally repeating or dipping).
  for i in 0..<100 {
    let candidate = if i % 3 == 0 && i > 0 {
      Int64::from_int((i - 1) * 60)
    } else {
      Int64::from_int(i * 60)
    }
    bridge.advance(candidate * 1000L)
  }
  // The largest accepted timestamp: i = 98 hands 98 * 60 ms (i = 99 hands
  // the dip (99 - 1) * 60, which the clock must refuse).
  assert_eq(clock.monotonic_ms(), 98 * 60)
}

///|
test "advancing to a larger time resumes millisecond tracking" {
  let bridge = @hostabi.HostBridge::new(store_u16=(_, _) => (), battery_percent=() => {
    -1
  })
  let clock : &@driver.Clock = bridge
  bridge.advance(5000000L)
  bridge.advance(1000L)
  bridge.advance(6250000L)
  assert_eq(clock.monotonic_ms(), 6250)
}
