///|
test "wire button codes decode onto the semantic buttons" {
  debug_inspect(@hostabi.to_button(@hostabi.BTN_UP), content="Some(Up)")
  debug_inspect(@hostabi.to_button(@hostabi.BTN_DOWN), content="Some(Down)")
  debug_inspect(@hostabi.to_button(@hostabi.BTN_OK), content="Some(Ok)")
}

///|
test "invalid button codes decode to None, never to an input edge" {
  debug_inspect(@hostabi.to_button(-1), content="None")
  debug_inspect(@hostabi.to_button(3), content="None")
  debug_inspect(@hostabi.to_button(255), content="None")
  debug_inspect(@hostabi.to_button(2147483647), content="None")
  debug_inspect(@hostabi.to_button(-2147483648), content="None")
}
