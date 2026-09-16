///|
test "valid device SOC readings map to Some" {
  debug_inspect(battery_percent_from_soc(0), content="Some(0)")
  debug_inspect(battery_percent_from_soc(50), content="Some(50)")
  debug_inspect(battery_percent_from_soc(100), content="Some(100)")
}

///|
test "invalid device SOC readings map to None" {
  debug_inspect(battery_percent_from_soc(-1), content="None")
  debug_inspect(battery_percent_from_soc(-5), content="None")
  debug_inspect(battery_percent_from_soc(101), content="None")
  debug_inspect(battery_percent_from_soc(255), content="None")
}

///|
test "host stub reports no battery so the device path yields None" {
  // The host linker stub answers -1 (no gauge attached); the conversion
  // must turn that into the unknown reading.
  debug_inspect(device_battery_percent(), content="None")
}
