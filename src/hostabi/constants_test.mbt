///|
test "ABI constants pin the frozen v0 memory map" {
  inspect(@hostabi.FRAMEBUFFER_PTR, content="4096")
  inspect(@hostabi.FRAMEBUFFER_LEN, content="153600")
  inspect(@hostabi.ABI_HEAP_START, content="262144")
  assert_eq(
    @hostabi.FRAMEBUFFER_LEN,
    @core.LOGICAL_WIDTH * @core.LOGICAL_HEIGHT * 2,
  )
  assert_eq(@hostabi.ABI_HEAP_START, 262144)
  assert_eq(@hostabi.CAPTURE_PTR, 196608)
  assert_true(
    @hostabi.CAPTURE_PTR >= @hostabi.FRAMEBUFFER_PTR + @hostabi.FRAMEBUFFER_LEN,
  )
  assert_true(
    @hostabi.CAPTURE_PTR + @hostabi.CAPTURE_SAMPLES * 2 <=
    @hostabi.ABI_HEAP_START,
  )
  assert_true(
    @hostabi.ABI_HEAP_START >
    @hostabi.FRAMEBUFFER_PTR + @hostabi.FRAMEBUFFER_LEN,
  )
}

///|
test "button codes match the SDK contract" {
  inspect(@hostabi.BTN_UP, content="0")
  inspect(@hostabi.BTN_DOWN, content="1")
  inspect(@hostabi.BTN_OK, content="2")
}
