///|
/// Clamps one signed PCM16 sample into the wire range `-32768..=32767`.
///
/// Producers upstream of the ABI (the music engine's mixer, fixture signal
/// generators) may overshoot the 16-bit range; `host_pcm_write` carries raw
/// PCM16, so overshoot saturates at the range ends instead of wrapping.
/// Pure integer math — no floating point anywhere in the bridge (frozen ABI
/// v0 determinism requirement).
pub fn clamp_pcm16(sample : Int) -> Int {
  if sample < -32768 {
    -32768
  } else if sample > 32767 {
    32767
  } else {
    sample
  }
}

///|
/// Encodes one signed sample as the unsigned 16-bit bit pattern stored by
/// `store_u16`: the clamped sample is re-expressed as a two's-complement
/// 16-bit value in `0..=65535` (`-1` becomes `65535`, `-32768` becomes
/// `32768`). `i32.store16` writes exactly these low 16 bits, little-endian
/// per the WebAssembly ISA, producing PCM16 LE bytes on the wire.
///
/// Exposed so tests (and off-wasm tooling) can verify the exact bytes the
/// host receives without instantiating a wasm module.
pub fn pcm16_le_bits(sample : Int) -> Int {
  let clamped = clamp_pcm16(sample)
  if clamped < 0 {
    clamped + 65536
  } else {
    clamped
  }
}
