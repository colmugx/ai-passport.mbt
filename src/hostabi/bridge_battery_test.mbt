///|
test "battery wire sentinel -1 means unavailable" {
  let bridge = @hostabi.HostBridge::new(store_u16=(_, _) => (), battery_percent=() => {
    -1
  })
  let source : &@battery.BatterySource = bridge
  debug_inspect(source.percent(), content="None")
}

///|
test "battery wire percent passes through as Some" {
  let bridge = @hostabi.HostBridge::new(store_u16=(_, _) => (), battery_percent=() => {
    87
  })
  let source : &@battery.BatterySource = bridge
  debug_inspect(source.percent(), content="Some(87)")
}

///|
test "battery endpoints 0 and 100 stay readable" {
  let zero = @hostabi.HostBridge::new(store_u16=(_, _) => (), battery_percent=() => {
    0
  })
  let full = @hostabi.HostBridge::new(store_u16=(_, _) => (), battery_percent=() => {
    100
  })
  let zero_source : &@battery.BatterySource = zero
  let full_source : &@battery.BatterySource = full
  debug_inspect(zero_source.percent(), content="Some(0)")
  debug_inspect(full_source.percent(), content="Some(100)")
}

///|
test "millivolts have no ABI v0 import and stay unavailable" {
  let bridge = @hostabi.HostBridge::new(store_u16=(_, _) => (), battery_percent=() => {
    87
  })
  let source : &@battery.BatterySource = bridge
  debug_inspect(source.millivolts(), content="None")
}
