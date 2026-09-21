///|
/// Wire button delivery (exported as `passport_input`): `button` is
/// 0=Up 1=Down 2=Ok and `pressed` is 1=press 0=release. Unknown codes decode
/// to `None` and are ignored — a malformed host value never invents an input
/// edge. Events are latched into `InputState` and take effect at the next
/// `passport_frame`.
pub fn passport_input(button : Int, pressed : Int) -> Unit {
  match @hostabi.to_button(button) {
    Some(btn) =>
      if pressed != 0 {
        state.input.press(btn)
      } else {
        state.input.release(btn)
      }
    None => ()
  }
}

///|
/// Byte offset of the persistent linear-memory framebuffer
/// (exported as `passport_fb_ptr`; the frozen ABI value 4096).
pub fn passport_fb_ptr() -> Int {
  @hostabi.FRAMEBUFFER_PTR
}

///|
/// Byte length of the framebuffer region: 240 * 320 RGB565 uint16 = 153600
/// (exported as `passport_fb_len`).
pub fn passport_fb_len() -> Int {
  @hostabi.FRAMEBUFFER_LEN
}

///|
/// Whether a frame has been presented since the last consume, reported as
/// `1`/`0` for the wasm boundary (exported as `passport_frame_dirty`).
pub fn passport_frame_dirty() -> Int {
  if state.bridge.frame_dirty() {
    1
  } else {
    0
  }
}

///|
/// Clears the dirty flag after the host has blitted the framebuffer
/// (exported as `passport_frame_consume`).
pub fn passport_frame_consume() -> Unit {
  state.bridge.consume()
}
