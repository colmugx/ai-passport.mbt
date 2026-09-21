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
  priv audio : @hostabi.DeviceAudioMirror
  priv mut frame : @graphics.FrameView?
}

///|
priv struct DeviceSlot {
  mut runtime : DeviceRuntime?
}

///|
let device_slot : DeviceSlot = { runtime: None, }

///|
priv struct DeviceSoundRuntimeSlot {
  mut installed : Bool
}

///|
let device_sound_runtime_slot : DeviceSoundRuntimeSlot = { installed: false, }

///|
fn install_device_sound_runtime() -> Unit {
  if device_sound_runtime_slot.installed {
    return
  }
  install_sound_runtime(
    play_sound=fn(sound_id, looping) {
      let handle = @hostabi.sound_play(
        sound_id.reinterpret_as_int(),
        if looping {
          1
        } else {
          0
        },
      )
      if handle < 0 {
        None
      } else {
        Some(handle)
      }
    },
    pause_playback=@hostabi.sound_pause,
    resume_playback=@hostabi.sound_resume,
    stop_playback=@hostabi.sound_stop,
    playback_position_us=fn(handle) {
      let position = @hostabi.sound_position_us(handle)
      if position < 0L {
        None
      } else {
        Some(position)
      }
    },
  )
  device_sound_runtime_slot.installed = true
}

///|
fn install_device_capture_runtime() -> Unit {
  if device_capture_runtime_slot.installed {
    return
  }
  @sound_host.install_capture(
    start=@hostabi.capture_start,
    status=@hostabi.capture_status,
    stop=@hostabi.capture_stop,
    read=fn(out) { @hostabi.capture_read(out, out.length()) },
    dropped=@hostabi.capture_dropped,
  )
  device_capture_runtime_slot.installed = true
}

///|
fn install_device_display_runtime() -> Unit {
  if device_display_runtime_slot.installed {
    return
  }
  @display_host.install_display(
    width=@core.LOGICAL_WIDTH,
    height=@core.LOGICAL_HEIGHT,
    monochrome=false,
    backlight_level=@hostabi.device_backlight_level,
    set_backlight=@hostabi.device_set_backlight,
  )
  device_display_runtime_slot.installed = true
}

///|
fn install_device_power_runtime() -> Unit {
  if device_power_runtime_slot.installed {
    return
  }
  @power_host.install_power(
    request=@hostabi.device_power_request,
    wake_reason=@hostabi.device_wake_reason,
  )
  device_power_runtime_slot.installed = true
}

///|
priv struct DevicePowerRuntimeSlot {
  mut installed : Bool
}

///|
let device_power_runtime_slot : DevicePowerRuntimeSlot = { installed: false, }

///|
priv struct DeviceDisplayRuntimeSlot {
  mut installed : Bool
}

///|
let device_display_runtime_slot : DeviceDisplayRuntimeSlot = {
  installed: false,
}

///|
priv struct DeviceCaptureRuntimeSlot {
  mut installed : Bool
}

///|
let device_capture_runtime_slot : DeviceCaptureRuntimeSlot = {
  installed: false,
}

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
/// application entry's `passport_main`. The audio mirror always exists so
/// an application may acquire audio output after boot. Initial `None` seeds
/// the mirror with the transport's existing silent startup facts (volume 0,
/// muted) without publishing an extra write.
pub fn device_boot(create_app : () -> &@application.Application) -> Unit {
  install_device_sound_runtime()
  install_device_capture_runtime()
  install_device_display_runtime()
  install_device_power_runtime()
  if device_slot.runtime is Some(_) {
    abort("passport device runtime initialized twice")
  }
  let app = create_app()
  let audio = match app.audio_output() {
    Some(output) =>
      @hostabi.DeviceAudioMirror(
        initial_volume=output.volume,
        initial_muted=output.muted,
      )
    None => @hostabi.DeviceAudioMirror(initial_volume=0, initial_muted=true)
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
/// `ai_passport_mbt_app_update`: one device frame tick. `FrameContext`
/// contains only Host-global presentation facts; sound position belongs to
/// the particular `Playback` queried through `@audio.position`.
pub fn device_update() -> Unit {
  let runtime = require_runtime()
  runtime.app.update({
    now_us: @hostabi.device_now_us(),
    presentation_lead_us: PRESENTATION_LEAD_US,
  })
  match runtime.app.audio_output() {
    Some(output) => runtime.audio.sync(output.volume, muted=output.muted)
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
/// `ai_passport_mbt_input_event`: one recognized physical event from the C
/// button bridge. Press also preserves the legacy one-frame press pulse;
/// click, double click, and long press are delivered to the event callback.
pub fn device_input_event(code : Int, kind : Int) -> Unit {
  guard @hostabi.device_button(code) is Some(button) else {
    abort("device input received an unknown button code: \{code}")
  }
  let event = match kind {
    0 => @input.Press
    1 => @input.Click
    2 => @input.DoubleClick
    3 => @input.LongPress
    _ => abort("device input received an unknown event code: \{kind}")
  }
  let runtime = require_runtime()
  runtime.app.button_event(button, event)
  if event is @input.Press {
    runtime.app.button(button, true)
    runtime.app.button(button, false)
  }
}

///|
/// `ai_passport_mbt_audio_volume` / `ai_passport_mbt_audio_muted`, read by
/// C after the sound runtime starts muted. An application with no desired
/// audio output gets silence — volume 0, muted — never an invented default
/// volume. Live output changes after startup cross through DeviceAudioMirror.
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
