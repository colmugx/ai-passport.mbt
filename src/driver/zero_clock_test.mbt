///|
test "ZeroClock::monotonic_ms is stably zero" {
  let clock = @driver.ZeroClock::new()
  inspect(clock.monotonic_ms(), content="0")
  inspect(clock.monotonic_ms(), content="0")

  // Consumed through the trait object, same stable result.
  let obj : &@driver.Clock = clock
  inspect(obj.monotonic_ms(), content="0")
}

///|
test "ZeroClock::sleep_ms is a no-op that never panics" {
  let clock : &@driver.Clock = @driver.ZeroClock::new()
  clock.sleep_ms(ms=0)
  clock.sleep_ms(ms=1000)
  // Still functional and unchanged after "sleeping".
  inspect(clock.monotonic_ms(), content="0")
}
