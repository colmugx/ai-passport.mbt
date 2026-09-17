///|
/// No-audio wasm entry: a static marker-row application with no PCM path.
/// The project contract declares no assets, so the module imports no audio
/// host functions — the no-op PCM closure keeps `passport.host_pcm_write`
/// out of the module.

///|
struct AppState {
  bridge : @hostabi.HostBridge
  canvas : @graphics.Canvas
}

///|
/// Package-level state, built before `_start` returns; the exported
/// `passport_*` wrappers always reach the same state.
let state : AppState = {
  bridge: @hostabi.HostBridge::new(
    store_u16=@hostabi.store_u16,
    pcm_write=fn(_ptr : Int, _samples : Int) { () },
    battery_percent=@hostabi.host_battery_percent,
  ),
  canvas: @graphics.Canvas::logical(),
}

///|
/// Wasm entry (`_start`): one-time init, then return — the host paces
/// frames.
fn main {
  let _ = state
}

///|
/// One frame tick (exported as `passport_frame`): advance the clock, draw
/// the static marker row, present into the linear-memory framebuffer.
pub fn passport_frame(now_us : Int64) -> Unit {
  state.bridge.advance(now_us)
  draw()
  let sink : &@driver.DisplaySink = state.bridge
  sink.present(frame=state.canvas.frame_view())
}

///|
fn draw() -> Unit {
  let canvas = state.canvas
  canvas.clear(color=@core.Color::rgb(r=0, g=0, b=0))
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
/// 1=press 0=release. The static scene keeps no input state, so decoded
/// events are dropped; unknown codes are ignored.
pub fn passport_input(_button : Int, _pressed : Int) -> Unit {
  ()
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
