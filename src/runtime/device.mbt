///|
/// SDK-owned FoloToy Host runtime: drives one `&@application.Application`
/// through the native device ABI (the `ai_passport_mbt_*` symbols the C
/// `app_main` calls). The passport CLI's generated device entry re-exports
/// these; every device detail (display sink, clock, battery, button decode,
/// audio mirror, presentation calibration) lives here, never in the
/// application.
pub struct DeviceRuntime {
  priv app : &@application.Application
  priv sink : @hostabi.DeviceDisplaySink
  priv audio : @hostabi.DeviceAudioMirror?
  priv mut frame : @graphics.FrameView?
}

///|
priv struct DeviceSlot {
  mut runtime : DeviceRuntime?
}

///|
let device_slot : DeviceSlot = { runtime: None, }

///|
/// The value C expects from `ai_passport_mbt_probe` to prove MoonBit code
/// is linked and running.
pub const DEVICE_PROBE : Int = 0xA17E

///|
/// FoloToy hardware presentation calibration: the device clock leads the
/// reported playback position by 100 ms (100_000 us). Measured on hardware
/// — no lead landed clearly after the audible beat, +150 ms overshot into
/// an early lead, 100 ms lands on the beat. Handed to the application as
/// the generic presentation-lead fact; the Web Host reports 0.
const PRESENTATION_LEAD_US : Int64 = 100_000L

///|
/// `ai_passport_mbt_app_init`: creates the runtime exactly once from the
/// application entry's `passport_main`. An application with initial audio
/// output state gets a transport mirror seeded with it; one without audio
/// state wires no mirror at all.
pub fn device_boot(create_app : () -> &@application.Application) -> Unit {
  if device_slot.runtime is Some(_) {
    abort("passport device runtime initialized twice")
  }
  let app = create_app()
  let audio = match app.audio_output() {
    Some(output) =>
      Some(
        @hostabi.DeviceAudioMirror::new(
          initial_volume=output.volume,
          initial_muted=output.muted,
        ),
      )
    None => None
  }
  device_slot.runtime = Some({
    app,
    sink: @hostabi.DeviceDisplaySink::new(),
    audio,
    frame: None,
  })
}

///|
fn require_runtime() -> DeviceRuntime {
  match device_slot.runtime {
    Some(runtime) => runtime
    None => abort("passport device runtime used before initialization")
  }
}

///|
/// `ai_passport_mbt_app_update`: the application receives the monotonic
/// device clock and the transport's playback Option (`Some(position)` —
/// loop-boundary zero included — while the streaming task runs, `None` when
/// it does not), then any audio output delta is mirrored to the transport.
pub fn device_update() -> Unit {
  let runtime = require_runtime()
  runtime.app.update({
    now_us: @hostabi.device_now_us(),
    playback_position_us: @hostabi.device_playback_position_us(),
    presentation_lead_us: PRESENTATION_LEAD_US,
  })
  match runtime.audio {
    Some(mirror) =>
      match runtime.app.audio_output() {
        Some(output) => mirror.sync(output.volume, muted=output.muted)
        None => ()
      }
    None => ()
  }
}

///|
/// `ai_passport_mbt_app_draw`: renders the logical frame with the device
/// battery reading and holds it for the present call.
pub fn device_draw() -> Unit {
  let runtime = require_runtime()
  runtime.frame = Some(runtime.app.render(@hostabi.device_battery_percent()))
}

///|
/// `ai_passport_mbt_app_present`: presents the frame the last draw rendered
/// through the device display sink.
pub fn device_present() -> Unit {
  let runtime = require_runtime()
  guard runtime.frame is Some(frame) else {
    abort("passport device runtime presented before drawing")
  }
  let sink : &@driver.DisplaySink = runtime.sink
  sink.present(frame~)
}

///|
/// `ai_passport_mbt_input_press`: one raw physical press from the C button
/// bridge. The BSP reports a press pulse rather than a clean press/release
/// pair, so the pulse becomes exactly one `pressed` edge, released
/// immediately. Unknown codes are ignored.
pub fn device_input(code : Int) -> Unit {
  guard @hostabi.device_button(code) is Some(button) else { return }
  let runtime = require_runtime()
  runtime.app.button(button, true)
  runtime.app.button(button, false)
}

///|
/// `ai_passport_mbt_audio_volume` / `ai_passport_mbt_audio_muted`, read by
/// C once before the music transport starts. An application with no
/// desired audio output gets silence — volume 0, muted — never an invented
/// default volume.
pub fn device_audio_volume() -> Int {
  match require_runtime().app.audio_output() {
    Some(output) => output.volume
    None => 0
  }
}

///|
pub fn device_audio_muted() -> Int {
  match require_runtime().app.audio_output() {
    Some(output) => if output.muted { 1 } else { 0 }
    None => 1
  }
}
