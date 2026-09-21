// Black-box tests for @battery. The test-local sources below live OUTSIDE the
// battery package yet implement `BatterySource` and are consumed through
// `&BatterySource` — that is the whole point of the open trait: every backend
// implements it externally.

///|
/// A source with fixed readings; a `None` field models an unavailable reading.
struct FixedSource {
  percent_value : Int?
  millivolts_value : Int?
}

///|
impl BatterySource for FixedSource with fn percent(self) -> Int? {
  self.percent_value
}

///|
impl BatterySource for FixedSource with fn millivolts(self) -> Int? {
  self.millivolts_value
}

///|
/// Counts how many times each slot was actually read from the source, to
/// prove the cache never polls implicitly.
struct CountingSource {
  mut percent_reads : Int
  mut millivolt_reads : Int
}

///|
impl BatterySource for CountingSource with fn percent(self) -> Int? {
  self.percent_reads += 1
  Some(55)
}

///|
impl BatterySource for CountingSource with fn millivolts(self) -> Int? {
  self.millivolt_reads += 1
  Some(3700)
}

///|
/// Fieldless external source; stateless structs are not viable, so it carries
/// the `_unit` sentinel field.
struct NullSource {
  _unit : Unit
}

///|
impl BatterySource for NullSource with fn percent(self) -> Int? {
  let _ = self
  None
}

///|
impl BatterySource for NullSource with fn millivolts(self) -> Int? {
  let _ = self
  None
}

///|
test "fresh Battery::new has an empty cache; refresh fills it from the source" {
  let source : &@battery.BatterySource = FixedSource::{
    percent_value: Some(66),
    millivolts_value: Some(3750),
  }
  let battery = @battery.Battery::new(source~)
  debug_inspect(battery.percent(), content="None")
  debug_inspect(battery.millivolts(), content="None")
  battery.refresh()
  debug_inspect(battery.percent(), content="Some(66)")
  debug_inspect(battery.millivolts(), content="Some(3750)")
}

///|
test "Battery::fixture caches the DRIVER.md default 82 on refresh" {
  let battery = @battery.Battery::fixture(percent=82)
  debug_inspect(battery.percent(), content="None")
  battery.refresh()
  debug_inspect(battery.percent(), content="Some(82)")
  debug_inspect(battery.millivolts(), content="None")
}

///|
test "Battery::fixture clamps percent into 0..=100" {
  let high = @battery.Battery::fixture(percent=150)
  high.refresh()
  debug_inspect(high.percent(), content="Some(100)")

  let low = @battery.Battery::fixture(percent=-3)
  low.refresh()
  debug_inspect(low.percent(), content="Some(0)")

  // Exact boundaries pass through unchanged.
  let full = @battery.Battery::fixture(percent=100)
  full.refresh()
  debug_inspect(full.percent(), content="Some(100)")

  let empty = @battery.Battery::fixture(percent=0)
  empty.refresh()
  debug_inspect(empty.percent(), content="Some(0)")
}

///|
test "cache never polls implicitly: constructor does no I/O, one refresh reads each slot once" {
  let src = CountingSource::{ percent_reads: 0, millivolt_reads: 0, }
  let source : &@battery.BatterySource = src
  let battery = @battery.Battery::new(source~)

  // The constructor performs no I/O at all.
  inspect(src.percent_reads, content="0")
  inspect(src.millivolt_reads, content="0")

  // One refresh reads the percent slot exactly once.
  battery.refresh()
  inspect(src.percent_reads, content="1")
  inspect(src.millivolt_reads, content="1")

  // Three cached percent() reads never touch the source again.
  ignore(battery.percent())
  ignore(battery.percent())
  ignore(battery.percent())
  inspect(src.percent_reads, content="1")
  inspect(src.millivolt_reads, content="1")

  // A second refresh reads each slot exactly once more.
  battery.refresh()
  inspect(src.percent_reads, content="2")
  inspect(src.millivolt_reads, content="2")
}

///|
test "source returning None for both slots propagates without panicking" {
  let source : &@battery.BatterySource = FixedSource::{
    percent_value: None,
    millivolts_value: None,
  }
  let battery = @battery.Battery::new(source~)
  battery.refresh()
  debug_inspect(battery.percent(), content="None")
  debug_inspect(battery.millivolts(), content="None")
}

///|
test "percent-only source leaves millivolts as None" {
  let source : &@battery.BatterySource = FixedSource::{
    percent_value: Some(9),
    millivolts_value: None,
  }
  let battery = @battery.Battery::new(source~)
  battery.refresh()
  debug_inspect(battery.percent(), content="Some(9)")
  debug_inspect(battery.millivolts(), content="None")
}

///|
test "external struct implements BatterySource and is consumed via &BatterySource" {
  let source : &@battery.BatterySource = NullSource::{ _unit: (), }
  let battery = @battery.Battery::new(source~)
  battery.refresh()
  debug_inspect(battery.percent(), content="None")
  debug_inspect(battery.millivolts(), content="None")
}
