///|
test "single click waits, double click replaces it, and long press fires once" {
  let state = @input.GestureState::new()
  let events : Array[@input.ButtonEvent] = []
  let emit = fn(_button, event) { events.push(event) }
  assert_true(state.input(@input.Ok, true, 0L, emit))
  assert_true(state.input(@input.Ok, false, 100_000L, emit))
  state.advance(300_000L, emit)
  debug_inspect(events, content="[Press]")
  assert_true(state.input(@input.Ok, true, 350_000L, emit))
  assert_true(state.input(@input.Ok, false, 450_000L, emit))
  debug_inspect(events, content="[Press, Press, DoubleClick]")
  state.advance(900_000L, emit)
  debug_inspect(events, content="[Press, Press, DoubleClick]")
  assert_true(state.input(@input.Ok, true, 1_000_000L, emit))
  state.advance(2_500_000L, emit)
  state.advance(3_000_000L, emit)
  assert_true(state.input(@input.Ok, false, 3_100_000L, emit))
  debug_inspect(events, content="[Press, Press, DoubleClick, Press, LongPress]")
}

///|
test "different buttons overlap independently and repeated edges are ignored" {
  let state = @input.GestureState::new()
  let events : Array[(@input.Button, @input.ButtonEvent)] = []
  let emit = fn(button, event) { events.push((button, event)) }
  assert_true(state.input(@input.Up, true, 0L, emit))
  assert_true(state.input(@input.Down, true, 20_000L, emit))
  assert_false(state.input(@input.Up, true, 30_000L, emit))
  assert_true(state.input(@input.Up, false, 100_000L, emit))
  assert_false(state.input(@input.Up, false, 110_000L, emit))
  state.advance(410_000L, emit)
  state.advance(1_520_000L, emit)
  debug_inspect(
    events,
    content="[(Up, Press), (Down, Press), (Up, Click), (Down, LongPress)]",
  )
}
