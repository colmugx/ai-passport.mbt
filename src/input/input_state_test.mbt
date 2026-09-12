///|
test "fresh state reports every query false for all three buttons" {
  let input = @input.InputState::new()
  for btn in [@input.Up, @input.Down, @input.Ok] {
    inspect(input.pressed(btn), content="false")
    inspect(input.just_pressed(btn), content="false")
    inspect(input.just_released(btn), content="false")
  }
}

///|
test "press holds the button and latches just_pressed until advance" {
  let input = @input.InputState::new()
  input.press(@input.Up)
  inspect(input.pressed(@input.Up), content="true")
  inspect(input.just_pressed(@input.Up), content="true")
  input.advance()
  inspect(input.pressed(@input.Up), content="true")
  inspect(input.just_pressed(@input.Up), content="false")
}

///|
test "release drops the button and latches just_released until advance" {
  let input = @input.InputState::new()
  input.press(@input.Down)
  input.release(@input.Down)
  inspect(input.pressed(@input.Down), content="false")
  inspect(input.just_released(@input.Down), content="true")
  input.advance()
  inspect(input.pressed(@input.Down), content="false")
  inspect(input.just_released(@input.Down), content="false")
}

///|
test "release without a prior press is a complete no-op" {
  let input = @input.InputState::new()
  input.release(@input.Up)
  inspect(input.pressed(@input.Up), content="false")
  inspect(input.just_pressed(@input.Up), content="false")
  inspect(input.just_released(@input.Up), content="false")
  // Still a no-op after a frame boundary...
  input.advance()
  input.release(@input.Up)
  inspect(input.just_released(@input.Up), content="false")
  // ...and after a real press-release cycle has completed.
  input.press(@input.Up)
  input.release(@input.Up)
  input.advance()
  input.release(@input.Up)
  inspect(input.pressed(@input.Up), content="false")
  inspect(input.just_released(@input.Up), content="false")
}

///|
test "double press in the same frame stays held with a single just_pressed edge" {
  let input = @input.InputState::new()
  input.press(@input.Ok)
  input.press(@input.Ok)
  inspect(input.pressed(@input.Ok), content="true")
  inspect(input.just_pressed(@input.Ok), content="true")
  input.advance()
  inspect(input.pressed(@input.Ok), content="true")
  inspect(input.just_pressed(@input.Ok), content="false")
}

///|
test "pressing a still-held button in a later frame raises a new edge" {
  let input = @input.InputState::new()
  input.press(@input.Up)
  input.advance()
  inspect(input.pressed(@input.Up), content="true")
  inspect(input.just_pressed(@input.Up), content="false")
  input.press(@input.Up)
  inspect(input.pressed(@input.Up), content="true")
  inspect(input.just_pressed(@input.Up), content="true")
  input.advance()
  inspect(input.just_pressed(@input.Up), content="false")
}

///|
test "pressing Up does not affect the Down and Ok queries" {
  let input = @input.InputState::new()
  input.press(@input.Up)
  inspect(input.pressed(@input.Up), content="true")
  inspect(input.just_pressed(@input.Up), content="true")
  for btn in [@input.Down, @input.Ok] {
    inspect(input.pressed(btn), content="false")
    inspect(input.just_pressed(btn), content="false")
    inspect(input.just_released(btn), content="false")
  }
  // The independence holds both ways: acting on the other buttons while Up is
  // held leaves Up's state untouched.
  input.advance()
  input.press(@input.Down)
  input.release(@input.Up)
  inspect(input.pressed(@input.Up), content="false")
  inspect(input.just_released(@input.Up), content="true")
  inspect(input.pressed(@input.Down), content="true")
  inspect(input.just_pressed(@input.Down), content="true")
  inspect(input.pressed(@input.Ok), content="false")
}

///|
test "full press-release cycle works for each button" {
  for btn in [@input.Up, @input.Down, @input.Ok] {
    let input = @input.InputState::new()
    input.press(btn)
    input.advance()
    inspect(input.pressed(btn), content="true")
    input.release(btn)
    inspect(input.pressed(btn), content="false")
    inspect(input.just_released(btn), content="true")
    input.advance()
    inspect(input.just_released(btn), content="false")
  }
}

///|
test "advance clears the edges of all buttons while held state persists" {
  let input = @input.InputState::new()
  input.press(@input.Up)
  input.press(@input.Down)
  input.press(@input.Ok)
  input.press(@input.Up)
  input.advance()
  for btn in [@input.Up, @input.Down, @input.Ok] {
    inspect(input.pressed(btn), content="true")
    inspect(input.just_pressed(btn), content="false")
    inspect(input.just_released(btn), content="false")
  }
}

///|
test "Button and ButtonEvent are exhaustively matchable with Debug output" {
  fn button_name(btn : @input.Button) -> String {
    match btn {
      @input.Up => "Up"
      @input.Down => "Down"
      @input.Ok => "Ok"
    }
  }

  fn event_name(event : @input.ButtonEvent) -> String {
    match event {
      @input.Press => "Press"
      @input.Click => "Click"
      @input.DoubleClick => "DoubleClick"
      @input.LongPress => "LongPress"
    }
  }

  for pair in [(@input.Up, "Up"), (@input.Down, "Down"), (@input.Ok, "Ok")] {
    let (btn, name) = pair
    inspect(button_name(btn), content=name)
    debug_inspect(btn, content=name)
  }
  for
    pair in [
      (@input.Press, "Press"),
      (@input.Click, "Click"),
      (@input.DoubleClick, "DoubleClick"),
      (@input.LongPress, "LongPress"),
    ] {
    let (event, name) = pair
    inspect(event_name(event), content=name)
    debug_inspect(event, content=name)
  }
}
