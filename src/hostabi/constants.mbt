///|
/// Byte offset of the linear-memory framebuffer region (ABI v0 memory map,
/// internal and experimental).
///
/// Region `[FRAMEBUFFER_PTR, FRAMEBUFFER_PTR + FRAMEBUFFER_LEN)` holds the
/// 240x320 RGB565 frame, row-major, little-endian uint16 per pixel, index
/// `y * 240 + x`. The host (JS) creates its `Uint16Array` view at this byte
/// offset; the app writes it only through the `HostBridge` adapters or the
/// inline-WAT `store_u16` helper. This region sits below `ABI_HEAP_START`, so
/// the MoonBit heap (which starts at `heap-start-address = 262144`) never
/// allocates over it.
pub const FRAMEBUFFER_PTR : Int = 4096

///|
/// Byte length of the linear-memory framebuffer region: `240 * 320 * 2 =
/// 153600` bytes (one RGB565 uint16 per logical pixel, little-endian).
///
/// The wasm export `passport_fb_len` reports exactly this value.
pub const FRAMEBUFFER_LEN : Int = 153600

///|
/// First byte address of the MoonBit heap in the wasm app (the fixture app's
/// `moon.pkg` sets `heap-start-address = 262144`, four 64 KiB pages).
///
/// Region `[0, ABI_HEAP_START)` is ABI-reserved (framebuffer + guard/reserve);
/// the MoonBit GC never allocates there, which is what makes
/// raw byte-addressed access through inline WAT safe.
pub const ABI_HEAP_START : Int = 262144

///|
/// Host-written capture scratch region below the wasm heap. The Web Host
/// writes at most 1024 PCM16 samples here per `host_capture_read` call.
pub const CAPTURE_PTR : Int = 196608

///|
pub const CAPTURE_SAMPLES : Int = 1024

///|
/// Wire code for the semantic `Up` button on the `passport_input` import
/// (button codes are the frozen ABI v0 wire encoding of `@input.Button`).
pub const BTN_UP : Int = 0

///|
/// Wire code for the semantic `Down` button on the `passport_input` import.
pub const BTN_DOWN : Int = 1

///|
/// Wire code for the semantic `Ok` button on the `passport_input` import.
pub const BTN_OK : Int = 2
