///|
/// Battery reading source, implemented by each backend (device BSP in the
/// template repo; host fixtures for development; docs/DRIVER.md: "`percent()`
/// and optional `millivolts()`. Host default fixture: 82%. Cache on device;
/// do not poll every frame.").
///
/// `None` means the reading is unavailable or the read failed — callers
/// degrade (e.g. a HUD shows "--"), never crash. Real sources sit behind
/// slow device buses, which is why the SDK only reads them through the
/// explicit `Battery` cache below, never implicitly.
///
/// The trait is declared `pub(open)` so each backend implements it outside
/// this package; app-facing code only consumes `&BatterySource` values.
///
/// Verified implementation form (one `pub impl` per method; the `pub` makes
/// the impl visible outside the implementing package's main unit):
///
/// ```mbt nocheck
/// pub impl BatterySource for MySource with fn percent(self) -> Int? {
///   ...
/// }
///
/// pub impl BatterySource for MySource with fn millivolts(self) -> Int? {
///   ...
/// }
/// ```
///
/// # Example
/// ```mbt check
/// test {
///   let battery = Battery::fixture(percent=82)
///   battery.refresh()
///   debug_inspect(battery.percent(), content="Some(82)")
/// }
/// ```
pub(open) trait BatterySource {
  fn percent(Self) -> Int?
  fn millivolts(Self) -> Int?
}

///|
/// Private host development fixture source: always reports one fixed percent
/// and never provides millivolts (docs/DRIVER.md: "Host default fixture:
/// 82%"). Constructed only through `Battery::fixture`, which clamps the
/// percent into 0..=100 up front. Its impls stay package-private (`impl`,
/// not `pub impl`): a public impl may not depend on a private type, and the
/// fixture is never consumed outside this package.
priv struct FixtureSource {
  percent_value : Int
}

///|
impl BatterySource for FixtureSource with fn percent(self) -> Int? {
  Some(self.percent_value)
}

///|
impl BatterySource for FixtureSource with fn millivolts(self) -> Int? {
  let _ = self
  None
}
