///|
test "walker sheet exposes four 12x20 frames and every frame draws" {
  let sheet = State::new().walker_sheet()
  inspect(sheet.frame_count(), content="4")
  inspect(sheet.frame_width(), content="12")
  inspect(sheet.frame_height(), content="20")
  // Every frame renders cleanly on a plain canvas.
  let canvas = @graphics.Canvas::new(width=64, height=80)
  for frame in 0..<4 {
    canvas.sprite(sheet~, frame~, x=26, y=44)
  }
  // Out-of-range frames are silent no-ops.
  canvas.sprite(sheet~, frame=4, x=26, y=44)
}

///|
test "draw survives a full tree wrap while walking on both canvases" {
  let input = @input.InputState::new()
  // Three Up edges ramp the speed to its cap.
  input.press(@input.Up)
  let mut s = State::new().update(input~)
  input.advance()
  input.press(@input.Up)
  s = s.update(input~)
  input.advance()
  input.press(@input.Up)
  s = s.update(input~)
  input.advance()
  assert_eq(s.speed().level, 3)
  // Walk well past one wrap period (canvas width plus the 24 px margin):
  // sixty frames at speed 3 scrolls 180+ pixels.
  for _ in 0..<60 {
    s = s.update(input~)
    input.advance()
  }
  assert_true(s.scroll() > 144)
  s.draw(canvas=@graphics.Canvas::logical())
  s.draw(canvas=@graphics.Canvas::new(width=64, height=80))
}

///|
test "draw with a fresh state succeeds on the logical and a 64x80 canvas" {
  let state = State::new()
  state.draw(canvas=@graphics.Canvas::logical())
  state.draw(canvas=@graphics.Canvas::new(width=64, height=80))
}
