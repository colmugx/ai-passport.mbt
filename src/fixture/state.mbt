///|
/// The Wasm host-boundary test fixture: the smallest MAIN package that
/// proves the SDK Wasm host boundary end-to-end (ABI v0, internal and
/// experimental). One `FixtureState` value lives in the package-level
/// `state` global so the exported `passport_*` wrappers — plain functions
/// the JS host calls across the wasm boundary — always reach the same
/// canvas, input state, battery cache and bridge. Frame content is a pure
/// function of the frame index, the input-derived selection, the mute flag
/// and the fixture battery reading: deterministic, integer-only, with no
/// floating point anywhere (R1 frozen fixture contract).

///|
/// Highest selection row index (rows are `y = 20 + sel * 8`, `sel` in
/// `0..=9`; frozen contract).
const SEL_MAX : Int = 9

///|
/// Fixture master volume mirrored to the host once at init; drives the
/// volume bar height `160 * volume / 100 = 112` rows (frozen contract).
const FIXTURE_VOLUME : Int = 70

///|
/// All fixture state. Constructed once during toplevel initialization and
/// never replaced; per-frame mutation happens through the `mut` fields.
struct FixtureState {
  bridge : @hostabi.HostBridge
  canvas : @graphics.Canvas
  input : @input.InputState
  battery : @battery.Battery
  /// Frame index `N` (the first `passport_frame` call is frame 0).
  mut frame : Int
  /// Selection row index, `0..=9`.
  mut sel : Int
  /// Mute flag: true draws the white block and reports `host_set_muted(1)`.
  mut muted : Bool
  /// Master volume (fixture constant 70), mirrored to the host at init.
  volume : Int
}

///|
/// Builds the fixture state over the real wasm bridge: the bridge's
/// `BatterySource` role backs the battery cache, so `refresh()` performs a
/// real `host_battery_percent` import call.
fn FixtureState::make() -> FixtureState {
  let bridge = @hostabi.new_wasm_bridge()
  let source : &@battery.BatterySource = bridge
  {
    bridge,
    canvas: @graphics.Canvas::logical(),
    input: @input.InputState::new(),
    battery: @battery.Battery::new(source~),
    frame: 0,
    sel: 0,
    muted: false,
    volume: FIXTURE_VOLUME,
  }
}

///|
/// Package-level fixture state. Toplevel initialization runs before `_start`
/// returns, and the host calls no `passport_*` export before `_start`, so
/// every export sees fully built state.
let state : FixtureState = FixtureState::make()

///|
/// Wasm entry point (exported as `_start` by default): performs one-time
/// initialization and RETURNS — there is no loop, the host paces frames by
/// calling `passport_frame`. Mirrors the master volume to the host exactly
/// once; mute starts audible.
fn main {
  @hostabi.host_set_volume(state.volume)
  @hostabi.host_set_muted(0)
}
