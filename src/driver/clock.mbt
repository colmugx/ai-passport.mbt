///|
/// Monotonic time and sleep, implemented by each backend (docs/DRIVER.md:
/// "Monotonic time, sleep/yield, frame delta. Do not base app timing on wall
/// clock.").
///
/// `monotonic_ms` may wrap at any point — applications must compare deltas
/// between consecutive reads, never absolute values. On the device it comes
/// from a hardware timer tick; on the host from the runtime's monotonic
/// source (landing with the deferred host preview). In both cases the value
/// is monotonic within a wrap window and never derived from the wall clock.
///
/// The trait is declared `pub(open)` so each backend implements it outside
/// this package; app-facing code only consumes `&Clock` values.
///
/// Verified implementation form (one `pub impl` per method; the `pub` makes
/// the impl visible outside the implementing package's main unit):
///
/// ```mbt nocheck
/// pub impl Clock for MyClock with fn monotonic_ms(self) -> Int {
///   ...
/// }
///
/// pub impl Clock for MyClock with fn sleep_ms(self, ms~ : Int) -> Unit {
///   ...
/// }
/// ```
///
/// # Example
/// ```mbt check
/// test {
///   let clock : &@driver.Clock = @driver.ZeroClock::new()
///   clock.sleep_ms(ms=16)
///   inspect(clock.monotonic_ms(), content="0")
/// }
/// ```
pub(open) trait Clock {
  fn monotonic_ms(Self) -> Int
  fn sleep_ms(Self, ms~ : Int) -> Unit
}
