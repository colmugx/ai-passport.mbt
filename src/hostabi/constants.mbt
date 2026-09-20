///|
/// Byte offset of the linear-memory framebuffer region (ABI v0 memory map,
/// internal and experimental).
///
/// Region `[FRAMEBUFFER_PTR, FRAMEBUFFER_PTR + FRAMEBUFFER_LEN)` holds the
/// 120x160 RGB565 frame, row-major, little-endian uint16 per pixel, index
/// `y * 120 + x`. The host (JS) creates its `Uint16Array` view at this byte
/// offset; the app writes it only through the `HostBridge` adapters or the
/// inline-WAT `store_u16` helper. This region sits below `ABI_HEAP_START`, so
/// the MoonBit heap (which starts at `heap-start-address = 65536`) never
/// allocates over it.
pub const FRAMEBUFFER_PTR : Int = 4096

///|
/// Byte length of the linear-memory framebuffer region: `120 * 160 * 2 =
/// 38400` bytes (one RGB565 uint16 per logical pixel, little-endian).
///
/// The wasm export `passport_fb_len` reports exactly this value.
pub const FRAMEBUFFER_LEN : Int = 38400

///|
/// First byte address of the MoonBit heap in the wasm app (the fixture app's
/// `moon.pkg` sets `heap-start-address = 65536`, one 64 KiB page).
///
/// Region `[0, ABI_HEAP_START)` is ABI-reserved (framebuffer + guard/reserve);
/// the MoonBit GC never allocates there, which is what makes
/// raw byte-addressed access through inline WAT safe.
pub const ABI_HEAP_START : Int = 65536

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
