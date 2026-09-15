///|
/// Decodes a wire button code handed to the `passport_input` wasm export
/// (0 = `BTN_UP`, 1 = `BTN_DOWN`, 2 = `BTN_OK`) into the semantic
/// `@input.Button` value (AGENTS.md rule 5: apps only ever see `Up`, `Down`,
/// `Ok`). Any other code — including negatives — decodes to `None`, so a
/// malformed host value degrades instead of inventing an input edge.
///
/// Fixture apps call this at the top of `passport_input` before forwarding to
/// `InputState::press` / `InputState::release`.
pub fn to_button(code : Int) -> @input.Button? {
  if code == BTN_UP {
    Some(@input.Up)
  } else if code == BTN_DOWN {
    Some(@input.Down)
  } else if code == BTN_OK {
    Some(@input.Ok)
  } else {
    None
  }
}
