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
/// Byte offset of the PCM staging buffer in linear memory (ABI v0 memory
/// map). Immediately follows the framebuffer region.
///
/// `HostBridge`'s `PcmSink` adapter stages one chunk here — as PCM16
/// little-endian uint16 samples — before handing the region to the host via
/// `host_pcm_write(PCM_STAGE_PTR, samples)`. The host copies the samples out
/// before the call returns, so the next write may reuse the region.
pub const PCM_STAGE_PTR : Int = 42496

///|
/// Byte capacity of the PCM staging buffer: 16384 bytes.
///
/// At 2 bytes per PCM16 sample this stages exactly `PCM_STAGE_CAPACITY_SAMPLES`
/// samples per `host_pcm_write` call.
pub const PCM_STAGE_CAPACITY_BYTES : Int = 16384

///|
/// Sample capacity of the PCM staging buffer: `PCM_STAGE_CAPACITY_BYTES / 2 =
/// 8192` PCM16 samples.
///
/// `PcmSink::write` chunks caller requests larger than this into consecutive
/// full-capacity staging rounds (plus one short tail chunk), so the staging
/// region is never overrun.
pub const PCM_STAGE_CAPACITY_SAMPLES : Int = 8192

///|
/// First byte address of the MoonBit heap in the wasm app (the fixture app's
/// `moon.pkg` sets `heap-start-address = 65536`, one 64 KiB page).
///
/// Region `[0, ABI_HEAP_START)` is ABI-reserved (framebuffer + PCM staging +
/// guard/reserve); the MoonBit GC never allocates there, which is what makes
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

///|
/// Sample rate of the PCM stream crossing the ABI: 16000 Hz signed PCM16
/// mono, the device baseline also pinned by `@audio.SAMPLE_RATE`.
///
/// The equality with `@audio.SAMPLE_RATE` is asserted by the package tests;
/// if the audio baseline ever moves, this ABI fact must move with it (and the
/// host must be updated in lockstep).
pub const PCM_SAMPLE_RATE : Int = 16000
