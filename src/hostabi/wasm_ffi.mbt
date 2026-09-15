///|
/// Wasm-target-gated raw ABI v0 surface (internal, experimental). This file
/// is compiled ONLY for the `wasm` backend (`moon.pkg` targets gating): the
/// externs declare imports from the `"passport"` module that the JS host
/// must provide at instantiation, so a native or js build would not link,
/// and a wasm test runner (moonrun) cannot supply the imports either — which
/// is why every test file in this package is gated to `native` + `js` (work
/// log ruling 2). Wasm-side coverage comes from the integration tests
/// against the real artifact.

///|
/// Host battery reading for the fixture: `0..=100`, or `-1` = unavailable.
pub fn host_battery_percent() -> Int = "passport" "host_battery_percent"

///|
/// Hands `samples` PCM16 LE mono samples (16000 Hz) at byte offset `ptr` in
/// linear memory to the host. The host copies the region before returning,
/// so the app may restage immediately. `samples` never exceeds
/// `PCM_STAGE_CAPACITY_SAMPLES` when written through `HostBridge`.
pub fn host_pcm_write(ptr : Int, samples : Int) -> Unit = "passport" "host_pcm_write"

///|
/// Master output gain, `0..=100`. Called directly by app code (no bridge
/// adapter owns volume in v0).
pub fn host_set_volume(volume : Int) -> Unit = "passport" "host_set_volume"

///|
/// Master mute switch, `0` = audible, `1` = muted. Called directly by app
/// code (the fixture's `Ok` button toggles it).
pub fn host_set_muted(muted : Int) -> Unit = "passport" "host_set_muted"

///|
/// Host's best-effort playback position in microseconds of normalized PCM
/// output since playback start. Monotonic while audio plays; apps must
/// compare deltas, never absolute values (same discipline as `Clock`).
pub fn host_playback_pos_us() -> Int64 = "passport" "host_playback_pos_us"

///|
/// Inline-WAT store of one 16-bit little-endian value at byte address `addr`.
///
/// `i32.store16` writes the low 16 bits of `value` in little-endian byte
/// order. Little-endian is guaranteed by the WebAssembly ISA itself (the
/// spec defines linear memory as byte-addressed little-endian) — not by host
/// chance — so the same binary produces identical bytes on every wasm
/// engine. This and `load_u16` are the ONLY raw memory accesses in the ABI;
/// no MoonBit object address is ever read or exposed (work log ruling 3).
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
/// Fixture wiring pattern (`src/fixture`, W3):
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
/// The remaining externs (`host_set_volume`, `host_set_muted`,
/// `host_playback_pos_us`) stay direct app-level calls.
pub fn new_wasm_bridge() -> HostBridge {
  HostBridge::new(
    store_u16~,
    pcm_write=host_pcm_write,
    battery_percent=host_battery_percent,
  )
}
