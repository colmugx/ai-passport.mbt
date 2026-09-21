///|
test "capture session reports state, reads PCM16, and counts overflow" {
  let status = Ref(1)
  let reads = Ref(0)
  let stopped = Ref(false)
  @sound_runtime.install_capture(
    @sound_runtime.CaptureRuntime::new(
      start=fn() {
        status.val = 3
        3
      },
      status=fn() { status.val },
      stop=fn() {
        stopped.val = true
        status.val = 1
      },
      read=fn(out) {
        out[0] = -32768
        out[1] = 32767
        reads.val += 1
        2
      },
      dropped=fn() { 7 },
    ),
  )
  assert_eq(capture_status(), Idle)
  assert_eq(capture_start(), Recording)
  let samples = FixedArray::make(4, 0)
  assert_eq(capture_read(samples), 2)
  assert_eq(samples[0], -32768)
  assert_eq(samples[1], 32767)
  assert_eq(reads.val, 1)
  assert_eq(capture_dropped_samples(), 7)
  capture_stop()
  assert_true(stopped.val)
  assert_eq(capture_status(), Idle)
}
