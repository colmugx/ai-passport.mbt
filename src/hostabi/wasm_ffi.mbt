///|
/// Wasm-target-gated raw ABI v0 surface (internal, experimental). This file
/// is compiled ONLY for the `wasm` backend (`moon.pkg` targets gating): the
/// externs declare imports from the `"passport"` module that the JS host
/// must provide at instantiation, so a native or js build would not link,
/// and a wasm test runner (moonrun) cannot supply the imports either — which
/// is why every test file in this package is gated to `native` + `js`.
/// Wasm-side coverage comes from the integration tests
/// against the real artifact.

///|
/// Host battery reading for the fixture: `0..=100`, or `-1` = unavailable.
pub fn host_battery_percent() -> Int = "passport" "host_battery_percent"

///|
pub fn host_backlight_level() -> Int = "passport" "host_backlight_level"

///|
pub fn host_set_backlight(level : Int) -> Unit = "passport" "host_set_backlight"

///|
/// Master output gain, `0..=100`. Called directly by app code (no bridge
/// adapter owns volume in v0).
pub fn host_set_volume(volume : Int) -> Unit = "passport" "host_set_volume"

///|
/// Master mute switch, `0` = audible, `1` = muted. Called directly by app
/// code (the fixture's `Ok` button toggles it).
pub fn host_set_muted(muted : Int) -> Unit = "passport" "host_set_muted"

///|
/// Starts one sound-bank entry. Returns a non-negative playback handle, or
/// -1 when the Host has no free playback slot.
pub fn host_sound_play(sound_id : Int, looping : Int) -> Int = "passport" "host_sound_play"

///|
pub fn host_sound_pause(handle : Int) -> Unit = "passport" "host_sound_pause"

///|
pub fn host_sound_resume(handle : Int) -> Unit = "passport" "host_sound_resume"

///|
pub fn host_sound_stop(handle : Int) -> Unit = "passport" "host_sound_stop"

///|
/// Returns a playback position in microseconds, or -1 when the handle is no
/// longer live.
pub fn host_sound_position_us(handle : Int) -> Int64 = "passport" "host_sound_position_us"

///|
pub fn host_capture_start() -> Int = "passport" "host_capture_start"

///|
pub fn host_capture_status() -> Int = "passport" "host_capture_status"

///|
pub fn host_capture_stop() -> Unit = "passport" "host_capture_stop"

///|
/// Writes up to `max_samples` PCM16 samples at `CAPTURE_PTR` and returns the
/// count. The caller validates the count before reading linear memory.
pub fn host_capture_read(max_samples : Int) -> Int = "passport" "host_capture_read"

///|
pub fn host_capture_dropped() -> Int = "passport" "host_capture_dropped"

///|
/// Inline-WAT store of one 16-bit little-endian value at byte address `addr`.
///
/// `i32.store16` writes the low 16 bits of `value` in little-endian byte
/// order. Little-endian is guaranteed by the WebAssembly ISA itself (the
/// spec defines linear memory as byte-addressed little-endian) — not by host
/// chance — so the same binary produces identical bytes on every wasm
/// engine. This and `load_u16` are the ONLY raw memory accesses in the ABI:
/// the boundary passes integer addresses, lengths, and raw 16-bit patterns
/// only, and no MoonBit object address is ever read or exposed across it.
pub fn store_u16(addr : Int, value : Int) -> Unit = "(func (param $addr i32) (param $value i32) (i32.store16 (local.get $addr) (local.get $value)))"

///|
/// Inline-WAT load of one zero-extended 16-bit little-endian value at byte
/// address `addr` (result `0..=65535`). Mirrors `store_u16` for read-back
/// (integration tests, host-side debugging tools).
pub fn load_u16(addr : Int) -> Int = "(func (param $addr i32) (result i32) (i32.load16_u (local.get $addr)))"

///|
/// Constructs the real wasm bridge: the injected raw operations become the
/// inline-WAT `store_u16` helper and the `"passport"` externs.
///
/// Fixture wiring pattern (`src/fixture`):
///
/// ```mbt nocheck
/// let bridge = @hostabi.new_wasm_bridge()
/// // per frame:
/// bridge.advance(now_us=now_us)
/// // render into Canvas, then:
/// let sink : &DisplaySink = bridge
/// sink.present(frame=canvas.frame_view())
/// ```
///
/// The remaining master-output externs stay direct runtime calls.
pub fn new_wasm_bridge() -> HostBridge {
  HostBridge::new(store_u16~, battery_percent=host_battery_percent)
}
