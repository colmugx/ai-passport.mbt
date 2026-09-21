///|
fn install_web_sound_runtime() -> Unit {
  install_sound_runtime(
    play_sound=fn(sound_id, looping) {
      let handle = @hostabi.host_sound_play(
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
    pause_playback=@hostabi.host_sound_pause,
    resume_playback=@hostabi.host_sound_resume,
    stop_playback=@hostabi.host_sound_stop,
    playback_position_us=fn(handle) {
      let position = @hostabi.host_sound_position_us(handle)
      if position < 0L {
        None
      } else {
        Some(position)
      }
    },
  )
}

///|
fn install_web_capture_runtime() -> Unit {
  @sound_host.install_capture(
    start=@hostabi.host_capture_start,
    status=@hostabi.host_capture_status,
    stop=@hostabi.host_capture_stop,
    read=fn(out) {
      let mut written = 0
      while written < out.length() {
        let remaining = out.length() - written
        let limit = if remaining < @hostabi.CAPTURE_SAMPLES {
          remaining
        } else {
          @hostabi.CAPTURE_SAMPLES
        }
        let count = @hostabi.host_capture_read(limit)
        if count < 0 || count > limit {
          abort("Web Host returned an invalid capture count: \{count}")
        }
        for i in 0..<count {
          let raw = @hostabi.load_u16(@hostabi.CAPTURE_PTR + i * 2)
          out[written + i] = if raw < 32768 { raw } else { raw - 65536 }
        }
        written += count
        if count < limit {
          break
        }
      }
      written
    },
    dropped=@hostabi.host_capture_dropped,
  )
}

///|
fn install_web_display_runtime() -> Unit {
  @display_host.install_display(
    width=@core.LOGICAL_WIDTH,
    height=@core.LOGICAL_HEIGHT,
    monochrome=false,
    backlight_level=@hostabi.host_backlight_level,
    set_backlight=@hostabi.host_set_backlight,
  )
}

///|
/// Wasm-only wiring: the injected host operations become the real ABI v0
/// imports (`"passport"` externs from `hostabi`), so a native or js build
/// never links.
pub fn WebRuntime::new_wasm(app : &@application.Application) -> WebRuntime {
  install_web_sound_runtime()
  install_web_capture_runtime()
  install_web_display_runtime()
  new_wasm_installed(app)
}

///|
fn new_wasm_installed(app : &@application.Application) -> WebRuntime {
  WebRuntime::new(
    app~,
    bridge=@hostabi.HostBridge::new(
      store_u16=@hostabi.store_u16,
      battery_percent=@hostabi.host_battery_percent,
    ),
    set_volume=@hostabi.host_set_volume,
    set_muted=fn(muted : Bool) {
      @hostabi.host_set_muted(if muted { 1 } else { 0 })
    },
  )
}

///|
/// Installs Host operations before creating the application, so its entry
/// function may request microphone or playback capabilities during boot.
pub fn WebRuntime::boot_wasm(
  create_app : () -> &@application.Application,
) -> WebRuntime {
  install_web_sound_runtime()
  install_web_capture_runtime()
  install_web_display_runtime()
  new_wasm_installed(create_app())
}
