///|
/// Converts a raw device state-of-charge reading into battery data: only
/// 0..=100 is a valid charge percentage. Anything else — the -1 read
/// failure, or a chip value outside the valid range — maps to `None`, so
/// the caller renders an unknown reading instead of trusting a bad number.
fn battery_percent_from_soc(soc : Int) -> Int? {
  if soc >= 0 && soc <= 100 {
    Some(soc)
  } else {
    None
  }
}

///|
/// Current battery percentage for the portable application. The raw SOC
/// reading crosses the boundary unchanged — the C side owns the gauge over
/// the Host's shared bus, and -1 means unavailable — so hardware knowledge
/// ends at the FFI; this is the only value device draw paths feed into the
/// scene.
pub fn device_battery_percent() -> Int? {
  battery_percent_from_soc(battery_soc())
}
