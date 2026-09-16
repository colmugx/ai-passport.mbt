///|
test "device button codes map onto the semantic buttons" {
  // Codes 0/1/2 are fixed by the C button_bridge.h ABI.
  debug_inspect(device_button(0), content="Some(Up)")
  debug_inspect(device_button(1), content="Some(Down)")
  debug_inspect(device_button(2), content="Some(Ok)")
}

///|
test "unknown device button codes degrade to None" {
  debug_inspect(device_button(3), content="None")
  debug_inspect(device_button(-1), content="None")
}
