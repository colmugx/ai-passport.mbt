///|
/// The smallest valid application: a static marker row with no audio state
/// at all. `audio_output` is `None` — no volume, no mute, no PCM, no fake
/// playback state — and button edges are dropped by the static scene. The
/// generated Host entries supply every platform detail around it.
pub struct MarkerApp {
  canvas : @graphics.Canvas
}

///|
pub fn MarkerApp::new() -> MarkerApp {
  { canvas: @graphics.Canvas::logical(), }
}

///|
pub fn MarkerApp::draw(self : MarkerApp) -> Unit {
  let canvas = self.canvas
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
pub fn MarkerApp::frame(self : MarkerApp) -> @graphics.FrameView {
  self.draw()
  self.canvas.frame_view()
}

///|
impl @application.Application for MarkerApp with fn update(
  self,
  _ctx : @application.FrameContext,
) -> Unit {
  let _ = self
}

///|
impl @application.Application for MarkerApp with fn button(
  self,
  _button : @input.Button,
  _pressed : Bool,
) -> Unit {
  let _ = self
}

///|
impl @application.Application for MarkerApp with fn render(
  self,
  _battery_percent : Int?,
) -> @graphics.FrameView {
  self.frame()
}

///|
impl @application.Application for MarkerApp with fn audio_output(self) -> @application.AudioOutput? {
  let _ = self
  None
}

///|
pub fn passport_main() -> &@application.Application {
  MarkerApp::new()
}
