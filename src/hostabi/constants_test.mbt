///|
test "ABI constants pin the frozen v0 memory map" {
  inspect(@hostabi.FRAMEBUFFER_PTR, content="4096")
  inspect(@hostabi.FRAMEBUFFER_LEN, content="38400")
  inspect(@hostabi.PCM_STAGE_PTR, content="42496")
  inspect(@hostabi.PCM_STAGE_CAPACITY_BYTES, content="16384")
  inspect(@hostabi.ABI_HEAP_START, content="65536")
  // The framebuffer and PCM regions tile contiguously from the null page
  // guard; everything below ABI_HEAP_START is ABI-reserved.
  assert_eq(
    @hostabi.FRAMEBUFFER_LEN,
    @core.LOGICAL_WIDTH * @core.LOGICAL_HEIGHT * 2,
  )
  assert_eq(
    @hostabi.PCM_STAGE_PTR,
    @hostabi.FRAMEBUFFER_PTR + @hostabi.FRAMEBUFFER_LEN,
  )
  // The heap starts one page in; [0xE600, 0xFFFF] between the PCM region and
  // the heap stays unassigned reserve (ABI v0 memory map).
  assert_eq(@hostabi.PCM_STAGE_PTR + @hostabi.PCM_STAGE_CAPACITY_BYTES, 58880)
  assert_eq(@hostabi.ABI_HEAP_START, 65536)
  assert_true(
    @hostabi.ABI_HEAP_START >
    @hostabi.PCM_STAGE_PTR + @hostabi.PCM_STAGE_CAPACITY_BYTES,
  )
}

///|
test "PCM staging capacity relates to its byte capacity" {
  // Two bytes per PCM16 sample.
  assert_eq(
    @hostabi.PCM_STAGE_CAPACITY_SAMPLES,
    @hostabi.PCM_STAGE_CAPACITY_BYTES / 2,
  )
  inspect(@hostabi.PCM_STAGE_CAPACITY_SAMPLES, content="8192")
}

///|
test "button codes and PCM rate facts match the SDK contracts" {
  inspect(@hostabi.BTN_UP, content="0")
  inspect(@hostabi.BTN_DOWN, content="1")
  inspect(@hostabi.BTN_OK, content="2")
  inspect(@hostabi.PCM_SAMPLE_RATE, content="16000")
  assert_eq(@hostabi.PCM_SAMPLE_RATE, @audio.SAMPLE_RATE)
}
