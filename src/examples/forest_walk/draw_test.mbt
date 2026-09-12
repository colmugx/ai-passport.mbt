///|
test "draw runs clean on a small canvas, the logical canvas and a walker-sized canvas" {
  let state = State::new()
  state.draw(canvas=@graphics.Canvas::new(width=64, height=80))
  state.draw(canvas=@graphics.Canvas::logical())
  // The minimum interesting canvas: exactly walker-sized.
  state.draw(canvas=@graphics.Canvas::new(width=12, height=20))
}

///|
test "draw also handles walking and paused states" {
  let input = @input.InputState::new()
  input.press(@input.Up)
  let moving = State::new().update(input~)
  moving.draw(canvas=@graphics.Canvas::logical())
  // Fresh input snapshot with a pause edge for the paused scene.
  let pause_input = @input.InputState::new()
  pause_input.press(@input.Ok)
  let paused = moving.update(input=pause_input)
  assert_true(paused.paused())
  paused.draw(canvas=@graphics.Canvas::new(width=64, height=80))
}
