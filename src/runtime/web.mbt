///|
/// SDK-owned Web Host runtime: drives one `&@application.Application`
/// through the Wasm ABI v0 host boundary. The passport CLI's generated Web
/// entry constructs this and re-exports the `passport_*` functions; every
/// platform detail (bridge, clock, battery, input decode, audio mirroring)
/// lives here, never in the application.
pub struct WebRuntime {
  priv app : &@application.Application
  priv bridge : @hostabi.HostBridge
  priv battery : @battery.Battery
  priv set_volume : (Int) -> Unit
  priv set_muted : (Bool) -> Unit
  // Host-applied volume/mute mirrors; only deltas cross the imports.
  priv mut applied_volume : Int?
  priv mut applied_muted : Bool?
}

///|
/// Wiring over injected host operations so the whole frame path is unit
/// testable off-wasm; `new_wasm` (wasm builds only) passes the real ABI v0
/// imports.
pub fn WebRuntime::new(
  app~ : &@application.Application,
  bridge~ : @hostabi.HostBridge,
  set_volume~ : (Int) -> Unit,
  set_muted~ : (Bool) -> Unit,
) -> WebRuntime {
  let source : &@battery.BatterySource = bridge
  {
    app,
    bridge,
    battery: @battery.Battery::new(source~),
    set_volume,
    set_muted,
    applied_volume: None,
    applied_muted: None,
  }
}

///|
/// One-time startup (the wasm `_start` tail): mirrors the application's
/// initial audio output state, when it has one. An application without
/// audio state never sends any — the module's audio imports sit unused, and
/// no default volume or mute is ever invented.
pub fn WebRuntime::start(self : WebRuntime) -> Unit {
  match self.app.audio_output() {
    Some(output) => {
      (self.set_volume)(output.volume)
      (self.set_muted)(output.muted)
      self.applied_volume = Some(output.volume)
      self.applied_muted = Some(output.muted)
    }
    None => ()
  }
}

///|
fn WebRuntime::frame_context(
  _self : WebRuntime,
  now_us : Int64,
) -> @application.FrameContext {
  { now_us, presentation_lead_us: 0L, }
}

///|
/// Mirrors the application's desired audio output; only the volume or mute
/// component that changed crosses its import (the application owns the
/// semantics; this side only mirrors state changes). `None` never invents
/// output state.
fn WebRuntime::sync_audio_output(self : WebRuntime) -> Unit {
  match self.app.audio_output() {
    Some(output) => {
      if self.applied_volume != Some(output.volume) {
        (self.set_volume)(output.volume)
        self.applied_volume = Some(output.volume)
      }
      if self.applied_muted != Some(output.muted) {
        (self.set_muted)(output.muted)
        self.applied_muted = Some(output.muted)
      }
    }
    None => ()
  }
}

///|
/// One ABI v0 frame tick (the `passport_frame` export).
pub fn WebRuntime::frame(self : WebRuntime, now_us : Int64) -> Unit {
  self.bridge.advance(now_us)
  self.app.update(self.frame_context(now_us))
  self.sync_audio_output()
  self.battery.refresh()
  let frame : @graphics.FrameView = self.app.render(self.battery.percent())
  let sink : &@driver.DisplaySink = self.bridge
  sink.present(frame~)
}

///|
/// Wire button delivery (the `passport_input` export): `code` is 0=Up
/// 1=Down 2=Ok and `pressed` is 1/0. Unknown codes are ignored.
pub fn WebRuntime::input(self : WebRuntime, code : Int, pressed : Int) -> Unit {
  match @hostabi.to_button(code) {
    Some(button) => self.app.button(button, pressed != 0)
    None => ()
  }
}

///|
/// Whether a frame was presented since the last consume, as the wasm
/// boundary integers 1/0 (the `passport_frame_dirty` export).
pub fn WebRuntime::frame_dirty(self : WebRuntime) -> Int {
  if self.bridge.frame_dirty() {
    1
  } else {
    0
  }
}

///|
/// Clears the dirty flag after the host has blitted the framebuffer (the
/// `passport_frame_consume` export).
pub fn WebRuntime::frame_consume(self : WebRuntime) -> Unit {
  self.bridge.consume()
}
