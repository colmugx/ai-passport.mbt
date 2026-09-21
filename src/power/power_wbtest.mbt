///|
test "application requests sleep and reads the reported wake cause" {
  let pending = Ref(false)
  let reason = Ref(0)
  let duration = Ref(0)
  @power_runtime.install(
    @power_runtime.PowerRuntime::new(
      request=fn(ms) {
        if pending.val {
          return 0
        }
        pending.val = true
        duration.val = ms
        reason.val = 0
        1
      },
      wake_reason=fn() { reason.val },
    ),
  )
  assert_eq(wake_reason(), None)
  assert_true(request_sleep())
  assert_eq(duration.val, -1)
  assert_true(!request_sleep())
  pending.val = false
  reason.val = 1
  assert_eq(wake_reason(), Some(Button))
  assert_true(request_timed_sleep(250))
  assert_eq(duration.val, 250)
  assert_eq(wake_reason(), None)
  pending.val = false
  reason.val = 2
  assert_eq(wake_reason(), Some(Timer))
}
