///|
/// A host-facts panel: every generic capability of the application contract
/// drawn as bars and markers — battery percentage, semantic button input,
/// monotonic host time, playback position, and the desired audio output
/// state. The same package serves the Web Host and a physical Host through
/// the generated entries; it owns no platform detail.
pub struct PanelApp {
  canvas : @graphics.Canvas
  mut volume : Int
  mut muted : Bool
  mut playback_x : Int
  mut time_x : Int
  mut playback_live : Bool
}

///|
pub fn PanelApp::new() -> PanelApp {
  {
    canvas: @graphics.Canvas::logical(),
    volume: STARTUP_VOLUME,
    muted: false,
    playback_x: 0,
    time_x: 0,
    playback_live: false,
  }
}

///|
/// Rows of the panel (y, height) — the browser suite probes these pixels.
pub const BATTERY_ROW : Int = 0

///|
pub const VOLUME_ROW : Int = 8

///|
pub const MUTE_ROW : Int = 16

///|
pub const PLAYBACK_ROW : Int = 24

///|
pub const TIME_ROW : Int = 32

///|
const VOLUME_STEP : Int = 10

///|
const VOLUME_MAX : Int = 100

///|
const STARTUP_VOLUME : Int = 80

///|
/// Battery bar width for a reading: a known `0..=100` percent scales onto
/// the logical width; an unknown reading (`None`) keeps a minimal stub so
/// the row is present but empty.
pub fn battery_bar_width(battery_percent : Int?) -> Int {
  match battery_percent {
    Some(percent) => percent * @core.LOGICAL_WIDTH / 100
    None => 0
  }
}

///|
/// Volume bar width for `0..=100`.
pub fn volume_bar_width(volume : Int) -> Int {
  volume * @core.LOGICAL_WIDTH / 100
}

///|
/// One semantic button edge: Up/Down step the remembered volume (clamped,
/// mute preserved), Ok toggles mute.
pub fn PanelApp::apply_button(
  self : PanelApp,
  button : @input.Button,
) -> Unit {
  match button {
    Up => {
      let next = self.volume + VOLUME_STEP
      self.volume = if next > VOLUME_MAX { VOLUME_MAX } else { next }
    }
    Down => {
      let next = self.volume - VOLUME_STEP
      self.volume = if next < 0 { 0 } else { next }
    }
    Ok => self.muted = !self.muted
  }
}

///|
impl @application.Application for PanelApp with fn update(
  self,
  ctx : @application.FrameContext,
) -> Unit {
  self.time_x = Int64::to_int((ctx.now_us / 100_000L) % 120L)
  match ctx.playback_position_us {
    Some(position) => {
      self.playback_live = true
      self.playback_x = Int64::to_int((position / 20_000L) % 120L)
    }
    None => self.playback_live = false
  }
}

///|
impl @application.Application for PanelApp with fn button(
  self,
  button : @input.Button,
  pressed : Bool,
) -> Unit {
  if pressed {
    self.apply_button(button)
  }
}

///|
impl @application.Application for PanelApp with fn render(
  self,
  battery_percent : Int?,
) -> @graphics.FrameView {
  let canvas = self.canvas
  canvas.clear(color=@core.Color::rgb(r=8, g=8, b=16))
  canvas.fill_rect(
    x=0,
    y=BATTERY_ROW,
    w=battery_bar_width(battery_percent),
    h=4,
    color=@core.Color::rgb(r=0, g=255, b=0),
  )
  canvas.fill_rect(
    x=0,
    y=VOLUME_ROW,
    w=volume_bar_width(self.volume),
    h=4,
    color=@core.Color::rgb(r=255, g=255, b=255),
  )
  canvas.fill_rect(
    x=0,
    y=MUTE_ROW,
    w=if self.muted {
      @core.LOGICAL_WIDTH
    } else {
      0
    },
    h=2,
    color=@core.Color::rgb(r=255, g=255, b=0),
  )
  if self.playback_live {
    canvas.fill_rect(
      x=self.playback_x,
      y=PLAYBACK_ROW,
      w=2,
      h=2,
      color=@core.Color::rgb(r=255, g=255, b=255),
    )
  }
  canvas.fill_rect(
    x=self.time_x,
    y=TIME_ROW,
    w=2,
    h=2,
    color=@core.Color::rgb(r=0, g=255, b=255),
  )
  canvas.frame_view()
}

///|
impl @application.Application for PanelApp with fn audio_output(
  self,
) -> @application.AudioOutput? {
  Some({ volume: self.volume, muted: self.muted })
}

///|
pub fn passport_main() -> &@application.Application {
  PanelApp::new()
}
