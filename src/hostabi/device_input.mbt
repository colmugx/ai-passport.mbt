///|
/// Maps one raw physical button code from the Host's C button bridge onto
/// the semantic `@input.Button` value. The codes are device-neutral facts
/// fixed by the C ABI (`button_bridge.h`): 0 = Up, 1 = Down, 2 = Ok;
/// unknown codes map to `None`, so a malformed value degrades instead of
/// inventing an input edge. No control meaning lives here — what a press
/// does is owned solely by the portable App, exactly as on the Wasm/Web
/// path. The C encoding matches the frozen ABI v0 wire codes, so the
/// shared `to_button` decoder stays the single mapping.
pub fn device_button(code : Int) -> @input.Button? {
  to_button(code)
}
