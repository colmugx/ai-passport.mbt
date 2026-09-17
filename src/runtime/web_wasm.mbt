///|
/// The no-op PCM closure keeping `host_pcm_write` out of the module: the
/// Web Host's PCM-asset mode is the only application audio transport, and
/// the host rejects a module that declares the streamed import while an
/// asset is configured, so the built module must never declare it.
fn pcm_noop(ptr : Int, samples : Int) -> Unit {
  let _ = ptr
  let _ = samples
}

///|
/// Wasm-only wiring: the injected host operations become the real ABI v0
/// imports (`"passport"` externs from `hostabi`), so a native or js build
/// never links.
pub fn WebRuntime::new_wasm(app : &@application.Application) -> WebRuntime {
  WebRuntime::new(
    app~,
    bridge=@hostabi.HostBridge::new(
      store_u16=@hostabi.store_u16,
      pcm_write=pcm_noop,
      battery_percent=@hostabi.host_battery_percent,
    ),
    playback_pos_us=@hostabi.host_playback_pos_us,
    set_volume=@hostabi.host_set_volume,
    set_muted=fn(muted : Bool) {
      @hostabi.host_set_muted(if muted { 1 } else { 0 })
    },
  )
}
