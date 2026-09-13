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
  // Eleven updates pump 11 * 533 = 5863 samples = 5.57 song ticks (the first
  // tick lands on update 2, then one every even update); the pause must
  // freeze that transport position too.
  assert_eq(s.player().position_ticks(), 5)
  let paused = tap(s, input, @input.Ok)
  assert_eq(paused.frame(), frame + 1)
  let mut frozen = paused
  for _ in 0..<6 {
    frozen = step(frozen, input)
    assert_eq(frozen.scroll(), scroll)
    assert_eq(frozen.walker_frame(), walker)
  }
  assert_eq(frozen.frame(), frame + 7)
  // Music pause = transport pause: tick and beat are exactly where they were.
  assert_eq(frozen.player().position_ticks(), 5)
  assert_eq(frozen.beat(), s.beat())
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
  // walker_frame stays 0 while standing still even though the music keeps
  // playing: the pose holds because the level is 0.
  assert_eq(frozen.walker_frame(), 0)
  // Thirty more standing updates (38 total) pump four eighth-ticks; the
  // first dotted-quarter beat crossed on update 24. The beat advanced but
  // the pose and the frozen scroll did not move.
  let mut standing = frozen
  for _ in 0..<30 {
    standing = step(standing, input)
  }
  assert_eq(standing.beat(), 1)
  assert_eq(standing.walker_frame(), 0)
  assert_eq(standing.scroll(), base + 5)
}

///|
test "walker_frame cycles 0..=3 with the dotted-quarter beat while walking" {
  let input = @input.InputState::new()
  let s1 = tap(State::new(), input, @input.Up)
  let mut s = s1
  let observed : Array[Int] = []
  // One large 6/8 beat is three ticks; a tick is 16000*60/(76*3) =
  // 4210.53 samples, i.e. 7.9 frames of 533 samples, so a beat is ~23.7
  // frames and four beats ~95 updates. Drive 120 updates to cover a full
  // pose cycle plus the wrap back to 1. Exact Bresenham carries put the
  // beat boundaries on updates 24, 48, 72, 95 and 119.
  for _ in 0..<120 {
    s = step(s, input)
    observed.push(s.walker_frame())
  }
  // observed[i] is the pose after update i+2 (the tap itself was update 1).
  assert_eq(observed[21], 0) // update 23: beat 0 still holds pose 0
  assert_eq(observed[22], 1) // update 24: first beat boundary -> pose 1
  assert_eq(observed[45], 1) // update 47
  assert_eq(observed[46], 2) // update 48: second beat -> pose 2
  assert_eq(observed[69], 2) // update 71
  assert_eq(observed[70], 3) // update 72: third beat -> pose 3
  assert_eq(observed[92], 3) // update 94
  assert_eq(observed[93], 0) // update 95: fourth beat wraps pose to 0
  assert_eq(observed[116], 0) // update 118
  assert_eq(observed[117], 1) // update 119: fifth beat wraps pose to 1
  assert_eq(observed[119], 1) // update 121
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

///|
test "player() exposes one shared transport whose tick advances across updates" {
  let input = @input.InputState::new()
  let state = State::new()
  let player = state.player()
  inspect(player.position_ticks(), content="0")
  // The showcase song is 24 song ticks long on every track (4 ticks per
  // eighth: 1+1+1+1+2 = 6 eighths, 3+3, 2+4, 3+1+2), so the whole-song loop
  // region is 24 ticks; the wrap itself is pinned by the wrap test below.
  let mut s = state
  for _ in 0..<10 {
    s = step(s, input)
  }
  // Ten updates pump 10 * 533 = 5330 samples = 5.07 song ticks: exactly five
  // sequencer steps have happened (ticks land on every even update).
  inspect(s.player().position_ticks(), content="5")
  // The getter hands out the one shared transport, not a copy.
  inspect(player.position_ticks(), content="5")
}

///|
test "sequencer tick wraps at the song length after enough updates" {
  // Song length: 24 song ticks (6 eighths at 4 ticks per eighth). One song
  // tick is 16000*60/(76*3*4) = 1052.63 samples = 1.976 frames of 533
  // samples, so steps land on every even update and one song loop is 24 *
  // 1.976 = 47.4 frames -> the wrap (the 24th step) lands on update 48.
  // Driving 58 updates covers 1.2x the song length.
  let input = @input.InputState::new()
  let mut s = State::new()
  for _ in 0..<47 {
    s = step(s, input)
  }
  assert_eq(s.player().position_ticks(), 23) // one step short of the 24-tick loop
  s = step(s, input)
  assert_eq(s.player().position_ticks(), 0) // update 48: the transport wrapped
  for _ in 0..<9 {
    s = step(s, input)
  }
  assert_eq(s.player().position_ticks(), 4) // 57 updates = 28 steps = 28 mod 24
}

///|
test "beat counts dotted-quarter beats and Ok pauses it with the music" {
  let input = @input.InputState::new()
  let mut s = tap(State::new(), input, @input.Up)
  // Three ticks are one large 6/8 beat; the first boundary lands on
  // update 24, the second (at the loop wrap, tick 6 -> 0) on update 48.
  for _ in 0..<23 {
    s = step(s, input)
  }
  assert_eq(s.beat(), 1)
  // Walking at speed 1: the pose is beat-synced, so it shifted with the beat.
  assert_eq(s.walker_frame(), 1)
  for _ in 0..<24 {
    s = step(s, input)
  }
  assert_eq(s.beat(), 2)
  // Ok pauses the transport: neither the beat nor the tick moves any more.
  let mut paused = tap(s, input, @input.Ok)
  assert_true(paused.paused())
  let beat = paused.beat()
  let tick = paused.player().position_ticks()
  let pose = paused.walker_frame()
  for _ in 0..<30 {
    paused = step(paused, input)
  }
  assert_eq(paused.beat(), beat)
  assert_eq(paused.player().position_ticks(), tick)
  assert_eq(paused.walker_frame(), pose)
}

///|
test "music advances only while unpaused: the tick is frozen across paused updates" {
  let input = @input.InputState::new()
  // Paused from the very first frame: nothing pumps, nothing steps.
  let mut s = tap(State::new(), input, @input.Ok)
  assert_true(s.paused())
  for _ in 0..<30 {
    s = step(s, input)
  }
  assert_eq(s.player().position_ticks(), 0)
  assert_eq(s.beat(), 0)
  // Resuming starts the transport again: the resume tap plus ten frames are
  // the only unpaused updates so far (11 * 533 samples = 5.57 song ticks).
  let mut resumed = tap(s, input, @input.Ok)
  assert_false(resumed.paused())
  for _ in 0..<10 {
    resumed = step(resumed, input)
  }
  assert_eq(resumed.player().position_ticks(), 5)
}
