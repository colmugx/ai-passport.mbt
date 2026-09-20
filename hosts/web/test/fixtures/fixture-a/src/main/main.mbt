///|
/// Fixture A: the smallest downstream-style application with NO audio — a
/// graphics/input app for the SDK Web Host. It exists to prove that the
/// passport CLI is application-generic: nothing in it (nor in the CLI) is
/// derived from any starter application.
///
/// Deterministic frame content:
/// - an 8x8 block at (0,0): red/green cycling on frame parity, flipping to
///   blue/yellow after the first Ok press (proves queued input lands);
/// - a static white marker row at y=80 (proves presentation happened).

///|
struct AppState {
  bridge : @hostabi.HostBridge
  canvas : @graphics.Canvas
  input : @input.InputState
  mut frame : Int
  mut flipped : Bool
}

///|
/// Package-level state, built before `_start` returns; the exported
/// `passport_*` wrappers always reach the same state.
let state : AppState = {
  bridge: @hostabi.HostBridge::new(
    store_u16=@hostabi.store_u16,
    battery_percent=@hostabi.host_battery_percent,
  ),
  canvas: @graphics.Canvas::logical(),
  input: @input.InputState::new(),
  frame: 0,
  flipped: false,
}

///|
/// Wasm entry (`_start`): one-time init, then return — the host paces frames.
fn main {
  let _ = state
}

///|
/// One frame tick (exported as `passport_frame`).
pub fn passport_frame(now_us : Int64) -> Unit {
  state.bridge.advance(now_us)
  if state.input.just_pressed(@input.Ok) {
    state.flipped = !state.flipped
  }
  draw()
  let sink : &@driver.DisplaySink = state.bridge
  sink.present(frame=state.canvas.frame_view())
  state.input.advance()
  state.frame += 1
}

///|
fn draw() -> Unit {
  let canvas = state.canvas
  canvas.clear(color=@core.Color::rgb(r=0, g=0, b=0))
  let first = if state.flipped {
    @core.Color::rgb(r=0, g=0, b=255)
  } else {
    @core.Color::rgb(r=255, g=0, b=0)
  }
  let second = if state.flipped {
    @core.Color::rgb(r=255, g=255, b=0)
  } else {
    @core.Color::rgb(r=0, g=255, b=0)
  }
  canvas.fill_rect(x=0, y=0, w=8, h=8, color=if state.frame % 2 == 0 { first } else { second })
  canvas.fill_rect(
    x=0,
    y=80,
    w=120,
    h=2,
    color=@core.Color::rgb(r=255, g=255, b=255),
  )
}

///|
/// Wire button delivery (exported as `passport_input`): 0=Up 1=Down 2=Ok,
/// 1=press 0=release; unknown codes are ignored.
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
/// Byte offset of the persistent framebuffer (exported as `passport_fb_ptr`).
pub fn passport_fb_ptr() -> Int {
  @hostabi.FRAMEBUFFER_PTR
}

///|
/// Byte length of the framebuffer (exported as `passport_fb_len`).
pub fn passport_fb_len() -> Int {
  @hostabi.FRAMEBUFFER_LEN
}

///|
/// Dirty flag since the last consume (exported as `passport_frame_dirty`).
pub fn passport_frame_dirty() -> Int {
  if state.bridge.frame_dirty() {
    1
  } else {
    0
  }
}

///|
/// Clears the dirty flag (exported as `passport_frame_consume`).
pub fn passport_frame_consume() -> Unit {
  state.bridge.consume()
}
