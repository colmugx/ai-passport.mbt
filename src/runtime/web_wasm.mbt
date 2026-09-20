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
/// Wasm-only wiring: the injected host operations become the real ABI v0
/// imports (`"passport"` externs from `hostabi`), so a native or js build
/// never links.
pub fn WebRuntime::new_wasm(app : &@application.Application) -> WebRuntime {
  install_web_sound_runtime()
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
