///|
enum FixtureSound {
  Ambient
  Hit
}

///|
impl @audio.Sound for FixtureSound with fn resource_id(self : FixtureSound) -> UInt {
  match self {
    Ambient => 0U
    Hit => 1U
  }
}

///|
struct SoundFixtureApp {
  canvas : @graphics.Canvas
  mut started : Bool
}

///|
impl @application.Application for SoundFixtureApp with fn update(self, _ctx) -> Unit {
  if !self.started {
    self.started = true
    let _ambient = @audio.play(Ambient, looping=true)
    let _hit1 = @audio.play(Hit)
    let _hit2 = @audio.play(Hit)
  }
}

///|
impl @application.Application for SoundFixtureApp with fn button(
  _self,
  _button,
  _pressed,
) -> Unit {
  ()
}

///|
impl @application.Application for SoundFixtureApp with fn render(
  self,
  _battery_percent,
) -> @graphics.FrameView {
  self.canvas.frame_view()
}

///|
impl @application.Application for SoundFixtureApp with fn audio_output(_self) -> @application.AudioOutput? {
  Some({ volume: 80, muted: false, })
}

///|
let app : SoundFixtureApp = {
  canvas: @graphics.Canvas::logical(),
  started: false,
}

///|
let state : @runtime.WebRuntime = @runtime.WebRuntime::new_wasm(app)

///|
fn main {
  state.start()
}

///|
pub fn passport_frame(now_us : Int64) -> Unit {
  state.frame(now_us)
}

///|
pub fn passport_input(button : Int, pressed : Int) -> Unit {
  state.input(button, pressed)
}

///|
pub fn passport_fb_ptr() -> Int {
  @hostabi.FRAMEBUFFER_PTR
}

///|
pub fn passport_fb_len() -> Int {
  @hostabi.FRAMEBUFFER_LEN
}

///|
pub fn passport_frame_dirty() -> Int {
  state.frame_dirty()
}

///|
pub fn passport_frame_consume() -> Unit {
  state.frame_consume()
}
