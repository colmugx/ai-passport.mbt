///|
test "the sink allocates one reusable logical row" {
  let sink = DeviceDisplaySink::new()
  assert_eq(sink.row.length(), @core.LOGICAL_WIDTH)
  // Repeated construction allocates independent buffers; nothing here
  // touches the display stubs, which abort by design on host builds.
  let again = DeviceDisplaySink::new()
  assert_eq(again.row.length(), @core.LOGICAL_WIDTH)
  again.row[0] = 0xABCD
  assert_eq(sink.row[0], 0)
}
