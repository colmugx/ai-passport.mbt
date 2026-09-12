///|
/// Steps one frame the way the host loop would: consume the input edges in
/// `State::update`, then cross the frame boundary with `InputState::advance`.
fn step(state : State, input : @input.InputState) -> State {
  let next = state.update(input~)
  input.advance()
  next
}

///|
/// Presses `btn` for exactly one frame: the edge is consumed by
/// `State::update` and cleared by the following `InputState::advance`.
fn tap(state : State, input : @input.InputState, btn : @input.Button) -> State {
  input.press(btn)
  step(state, input)
}

///|
test "Ok toggles pause only on a just_pressed edge" {
  let input = @input.InputState::new()
  let state = State::new()
  // No press this frame: no pause change.
  inspect(state.update(input~).paused(), content="false")
  // Press Ok -> paused.
  let paused = tap(state, input, @input.Ok)
  inspect(paused.paused(), content="true")
  // advance() cleared the edge: a plain update keeps the pause.
  let still = step(paused, input)
  inspect(still.paused(), content="true")
  // Pressing the still-held Ok after the boundary raises a fresh edge.
  let resumed = tap(still, input, @input.Ok)
  inspect(resumed.paused(), content="false")
}

///|
test "while paused scroll and walker_frame freeze but the frame keeps counting" {
  let input = @input.InputState::new()
  // Walk at speed 1: one tap frame plus 10 steps of world motion.
  let mut s = tap(State::new(), input, @input.Up)
  for _ in 0..<10 {
    s = step(s, input)
  }
  let scroll = s.scroll()
  let walker = s.walker_frame()
  let frame = s.frame()
  assert_true(scroll > 0)
  let paused = tap(s, input, @input.Ok)
  assert_eq(paused.frame(), frame + 1)
  let mut frozen = paused
  for _ in 0..<6 {
    frozen = step(frozen, input)
    assert_eq(frozen.scroll(), scroll)
    assert_eq(frozen.walker_frame(), walker)
  }
  assert_eq(frozen.frame(), frame + 7)
}

///|
test "speed keys still work while paused, without moving the world" {
  let input = @input.InputState::new()
  let paused = tap(State::new(), input, @input.Ok)
  inspect(paused.paused(), content="true")
  let faster = tap(paused, input, @input.Up)
  inspect(faster.speed().level, content="1")
  // Paused at speed 1: the world stays put.
  let held = step(faster, input)
  inspect(held.scroll(), content="0")
  let slower = tap(held, input, @input.Down)
  inspect(slower.speed().level, content="0")
}

///|
test "Up clamps at level 3 and Down clamps at level 0" {
  let input = @input.InputState::new()
  let s3 = tap(
    tap(tap(State::new(), input, @input.Up), input, @input.Up),
    input,
    @input.Up,
  )
  inspect(s3.speed().level, content="3")
  // A fourth Up stays at the cap.
  let s4 = tap(s3, input, @input.Up)
  inspect(s4.speed().level, content="3")
  // Two Downs step down to 1.
  let s1 = tap(tap(s4, input, @input.Down), input, @input.Down)
  inspect(s1.speed().level, content="1")
  // A Down at level 0 stays clamped.
  let s0 = tap(tap(s1, input, @input.Down), input, @input.Down)
  inspect(s0.speed().level, content="0")
  let s0b = tap(s0, input, @input.Down)
  inspect(s0b.speed().level, content="0")
}

///|
test "speed level drives scroll: +2 per frame at speed 2, frozen at speed 0" {
  let input = @input.InputState::new()
  let s2 = tap(tap(State::new(), input, @input.Up), input, @input.Up)
  assert_eq(s2.speed().level, 2)
  // The two speed-up taps already scrolled +1 and +2.
  let base = s2.scroll()
  assert_eq(base, 3)
  let after = step(s2, input)
  assert_eq(after.scroll(), base + 2)
  let after2 = step(after, input)
  assert_eq(after2.scroll(), base + 4)
  // Back down: the first Down tap still scrolls +1 at speed 1...
  let d1 = tap(after2, input, @input.Down)
  assert_eq(d1.speed().level, 1)
  assert_eq(d1.scroll(), base + 5)
  // ...the second lands at speed 0 and the scroll freezes in place.
  let s0 = tap(d1, input, @input.Down)
  assert_eq(s0.speed().level, 0)
  assert_eq(s0.scroll(), base + 5)
  let frozen = step(s0, input)
  assert_eq(frozen.scroll(), base + 5)
  // walker_frame stays 0 while standing still (all frames so far are < 8).
  assert_eq(frozen.walker_frame(), 0)
}

///|
test "walker_frame cycles 0..=3 while walking and wraps at frame 32" {
  let input = @input.InputState::new()
  let s1 = tap(State::new(), input, @input.Up)
  let mut s = s1
  let observed : Array[Int] = []
  for _ in 0..<33 {
    s = step(s, input)
    observed.push(s.walker_frame())
  }
  // observed[i] is the pose after frame i+2 (the tap itself was frame 1).
  // The pose is (frame / 8) % 4, so frames 8..15 pose 1, 16..23 pose 2,
  // 24..31 pose 3 and frame 32 wraps back to 0.
  assert_eq(observed[5], 0) // frame 7
  assert_eq(observed[6], 1) // frame 8
  assert_eq(observed[13], 1) // frame 15
  assert_eq(observed[14], 2) // frame 16
  assert_eq(observed[21], 2) // frame 23
  assert_eq(observed[22], 3) // frame 24
  assert_eq(observed[29], 3) // frame 31
  assert_eq(observed[30], 0) // frame 32: wrapped
  assert_eq(observed[32], 0) // frame 34
  for f in observed {
    assert_true(f >= 0 && f <= 3)
  }
}

///|
test "update never mutates the receiver" {
  let input = @input.InputState::new()
  let state = State::new()
  input.press(@input.Up)
  input.press(@input.Ok)
  let next = state.update(input~)
  // The receiver keeps its original snapshot...
  assert_eq(state.frame(), 0)
  assert_eq(state.speed().level, 0)
  assert_eq(state.paused(), false)
  assert_eq(state.scroll(), 0)
  // ...while the returned state moved on.
  assert_eq(next.frame(), 1)
  assert_eq(next.speed().level, 1)
  assert_eq(next.paused(), true)
  assert_eq(next.scroll(), 0)
}
