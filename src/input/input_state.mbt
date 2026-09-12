///|
/// Per-button frame state: the held flag plus the `just_pressed` and
/// `just_released` latches that `InputState::advance` clears at the frame
/// boundary. Private; never exposed through the public API.
priv struct BtnState {
  mut held : Bool
  mut just_pressed : Bool
  mut just_released : Bool
} derive(Debug)

///|
/// Creates a per-button cell with every flag cleared.
fn BtnState::fresh() -> BtnState {
  { held: false, just_pressed: false, just_released: false, }
}

///|
/// Frame-polled input state for the three semantic buttons.
///
/// `InputState::press` and `InputState::release` take effect immediately and
/// latch `just_pressed` / `just_released` edges; `InputState::advance` is the
/// end-of-frame boundary that clears those latches for every button while
/// held state persists. The three buttons are fully independent, and the
/// internal flags are deliberately private.
///
/// # Example
/// ```mbt check
/// test {
///   let input = InputState::new()
///   input.press(Up)
///   inspect(input.pressed(Up), content="true")
///   inspect(input.just_pressed(Up), content="true")
///   input.advance()
///   inspect(input.pressed(Up), content="true")
///   inspect(input.just_pressed(Up), content="false")
/// }
/// ```
pub struct InputState {
  priv up : BtnState
  priv down : BtnState
  priv ok : BtnState
} derive(Debug)

///|
/// Creates a state where every button is released and no edge is latched.
/// This is the only place `InputState` allocates; the per-frame transition
/// methods below are allocation-free.
///
/// # Example
/// ```mbt check
/// test {
///   let input = InputState::new()
///   inspect(input.pressed(Down), content="false")
///   inspect(input.just_pressed(Down), content="false")
///   inspect(input.just_released(Down), content="false")
/// }
/// ```
pub fn InputState::new() -> InputState {
  { up: BtnState::fresh(), down: BtnState::fresh(), ok: BtnState::fresh(), }
}

///|
/// Returns the private per-button cell holding `btn`'s state.
fn InputState::slot(self : InputState, btn : Button) -> BtnState {
  match btn {
    Up => self.up
    Down => self.down
    Ok => self.ok
  }
}

///|
/// Marks `btn` as held and latches its `just_pressed` edge, which stays true
/// until the next `InputState::advance`.
///
/// Pressing an already-held button again within the same frame is a no-op:
/// the latches stay unchanged so consumers see exactly one edge. Once
/// `InputState::advance` has run, pressing the still-held button again in a
/// later frame raises a fresh `just_pressed` edge.
///
/// # Example
/// ```mbt check
/// test {
///   let input = InputState::new()
///   input.press(Ok)
///   input.press(Ok)
///   inspect(input.just_pressed(Ok), content="true")
///   input.advance()
///   input.press(Ok)
///   inspect(input.pressed(Ok), content="true")
///   inspect(input.just_pressed(Ok), content="true")
/// }
/// ```
pub fn InputState::press(self : InputState, btn : Button) -> Unit {
  let b = self.slot(btn)
  if !(b.held && b.just_pressed) {
    b.held = true
    b.just_pressed = true
  }
}

///|
/// Marks `btn` as no longer held and latches its `just_released` edge, which
/// stays true until the next `InputState::advance`.
///
/// Releasing a button that is not held is a complete no-op: no
/// `just_released` edge is produced from nothing.
///
/// # Example
/// ```mbt check
/// test {
///   let input = InputState::new()
///   input.release(Down)
///   inspect(input.just_released(Down), content="false")
///   input.press(Down)
///   input.release(Down)
///   inspect(input.just_released(Down), content="true")
/// }
/// ```
pub fn InputState::release(self : InputState, btn : Button) -> Unit {
  let b = self.slot(btn)
  if b.held {
    b.held = false
    b.just_released = true
  }
}

///|
/// End-of-frame boundary: clears the `just_pressed` and `just_released`
/// latches of every button at once. Held state persists across frames. Call
/// this once per frame, after consuming the edges.
///
/// # Example
/// ```mbt check
/// test {
///   let input = InputState::new()
///   input.press(Up)
///   input.release(Up)
///   input.advance()
///   inspect(input.just_pressed(Up), content="false")
///   inspect(input.just_released(Up), content="false")
/// }
/// ```
pub fn InputState::advance(self : InputState) -> Unit {
  self.up.just_pressed = false
  self.up.just_released = false
  self.down.just_pressed = false
  self.down.just_released = false
  self.ok.just_pressed = false
  self.ok.just_released = false
}

///|
/// Returns whether `btn` is currently held. Held state persists across
/// `InputState::advance` until a matching `InputState::release`.
///
/// # Example
/// ```mbt check
/// test {
///   let input = InputState::new()
///   input.press(Ok)
///   input.advance()
///   inspect(input.pressed(Ok), content="true")
///   input.release(Ok)
///   inspect(input.pressed(Ok), content="false")
/// }
/// ```
pub fn InputState::pressed(self : InputState, btn : Button) -> Bool {
  self.slot(btn).held
}

///|
/// Returns whether `btn` was pressed during the current frame, i.e. since
/// the last `InputState::advance` (or since creation for the first frame).
///
/// # Example
/// ```mbt check
/// test {
///   let input = InputState::new()
///   input.press(Up)
///   inspect(input.just_pressed(Up), content="true")
///   input.advance()
///   inspect(input.just_pressed(Up), content="false")
/// }
/// ```
pub fn InputState::just_pressed(self : InputState, btn : Button) -> Bool {
  self.slot(btn).just_pressed
}

///|
/// Returns whether `btn` was released during the current frame, i.e. since
/// the last `InputState::advance` (or since creation for the first frame).
/// A release with no matching held state never produces an edge.
///
/// # Example
/// ```mbt check
/// test {
///   let input = InputState::new()
///   input.release(Ok)
///   inspect(input.just_released(Ok), content="false")
///   input.press(Ok)
///   input.release(Ok)
///   inspect(input.just_released(Ok), content="true")
/// }
/// ```
pub fn InputState::just_released(self : InputState, btn : Button) -> Bool {
  self.slot(btn).just_released
}
