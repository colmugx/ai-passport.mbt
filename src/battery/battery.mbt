///|
/// Explicit-poll cache facade over a `&BatterySource`. Real sources sit
/// behind slow device buses; the SDK never reads the source implicitly —
/// call `refresh()` at your own cadence (docs/DRIVER.md: "Cache on device;
/// do not poll every frame"). The constructor performs no I/O: both cache
/// slots start as `None` until the first `refresh()`.
///
/// # Example
/// ```mbt check
/// test {
///   let battery = @battery.Battery::fixture(percent=82)
///   debug_inspect(battery.percent(), content="None")
///   battery.refresh()
///   debug_inspect(battery.percent(), content="Some(82)")
/// }
/// ```
pub struct Battery {
  priv source : &BatterySource
  priv mut percent : Int?
  priv mut millivolts : Int?
}

///|
/// Wraps `source` in a fresh, empty cache. The constructor performs no I/O —
/// nothing touches the source until the first `refresh()`.
///
/// Any `&BatterySource` implementation can be wrapped; the implementation
/// form is shown on the `BatterySource` docs. A docstring block can neither
/// define new toplevels nor name this package's private fixture source, and
/// the public API intentionally has no concrete source type, so this example
/// is illustrative (`nocheck`) — the same flow is compiler-checked in the
/// package tests and in every other `# Example` block below.
///
/// # Example
/// ```mbt nocheck
/// struct ConstantSource {
///   _unit : Unit
/// }
///
/// impl BatterySource for ConstantSource with fn percent(self) -> Int? {
///   let _ = self
///   Some(70)
/// }
///
/// impl BatterySource for ConstantSource with fn millivolts(self) -> Int? {
///   let _ = self
///   None
/// }
///
/// test {
///   let source : &BatterySource = ConstantSource::{ _unit: (), }
///   let battery = Battery::new(source~)
///   // The constructor performed no I/O: the cache is still empty.
///   debug_inspect(battery.percent(), content="None")
///   battery.refresh()
///   debug_inspect(battery.percent(), content="Some(70)")
/// }
/// ```
pub fn Battery::new(source~ : &BatterySource) -> Battery {
  { source, percent: None, millivolts: None, }
}

///|
/// Host development fixture backed by a static source: its `percent()` is
/// always `clamp(percent, 0, 100)` and its `millivolts()` is always `None`
/// (docs/DRIVER.md: "Host default fixture: 82%").
///
/// # Example
/// ```mbt check
/// test {
///   let battery = @battery.Battery::fixture(percent=82)
///   battery.refresh()
///   debug_inspect(battery.percent(), content="Some(82)")
///   debug_inspect(battery.millivolts(), content="None")
/// }
/// ```
pub fn Battery::fixture(percent~ : Int) -> Battery {
  let source : &BatterySource = FixtureSource::{
    percent_value: percent.clamp(min=0, max=100),
  }
  Battery::new(source~)
}

///|
/// Reads the source exactly once per slot and updates both cache slots.
/// Call this at your own cadence — the SDK never refreshes implicitly, so a
/// render loop can keep the shared device bus idle between polls.
///
/// # Example
/// ```mbt check
/// test {
///   let battery = @battery.Battery::fixture(percent=40)
///   debug_inspect(battery.percent(), content="None")
///   battery.refresh()
///   debug_inspect(battery.percent(), content="Some(40)")
/// }
/// ```
pub fn Battery::refresh(self : Battery) -> Unit {
  self.percent = self.source.percent()
  self.millivolts = self.source.millivolts()
}

///|
/// Cached percent (0..=100), or `None` until the first `refresh()` — and
/// `None` from then on whenever the source could not provide a reading.
///
/// # Example
/// ```mbt check
/// test {
///   let battery = @battery.Battery::fixture(percent=40)
///   debug_inspect(battery.percent(), content="None") // cache starts empty
///   battery.refresh()
///   debug_inspect(battery.percent(), content="Some(40)")
/// }
/// ```
pub fn Battery::percent(self : Battery) -> Int? {
  self.percent
}

///|
/// Cached millivolts, or `None` until the first `refresh()` — and `None`
/// from then on whenever the source cannot provide a millivolt reading
/// (the fixture source never does).
///
/// # Example
/// ```mbt check
/// test {
///   let battery = @battery.Battery::fixture(percent=82)
///   battery.refresh()
///   debug_inspect(battery.millivolts(), content="None")
/// }
/// ```
pub fn Battery::millivolts(self : Battery) -> Int? {
  self.millivolts
}
