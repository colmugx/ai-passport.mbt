///|
/// Native-target-gated raw device ABI (internal). This file is compiled ONLY
/// for the `native` backend (`moon.pkg` targets gating): the `extern "c"`
/// declarations bind to the C bridge symbols that the device firmware links
/// (see `hosts/folotoy/ai-passport/components/`), so a js or wasm build
/// would not link them. Host-side native builds and tests link the
/// package's `native_stub.c` stand-ins instead — aborting display stubs, a
/// "no gauge" battery, frozen clocks and a recording output setter — which
/// keeps this whole surface honest and unit-testable off-device. Device-side
/// evidence comes from the real firmware build.

///|
/// Begin one display frame transaction on the C display bridge.
extern "c" fn display_begin() -> Unit = "ai_passport_display_begin"

///|
/// Hands one RGB565 row to the C display bridge. The bridge consumes the
/// samples synchronously and stores nothing, so the row is borrowed.
#borrow(row)
extern "c" fn display_row(y : Int, row : FixedArray[Int]) -> Unit = "ai_passport_display_row"

///|
/// End the display frame transaction started by `display_begin`.
extern "c" fn display_end() -> Unit = "ai_passport_display_end"

///|
/// Raw state-of-charge reading from the device battery bridge: 0..100, or
/// -1 when unavailable (gauge missing, unreadable, or not yet initialized).
/// The integer crosses the boundary unchanged.
extern "c" fn battery_soc() -> Int = "ai_passport_battery_soc"

///|
/// Transport availability fact from the C music stream (1 = the streaming
/// task started, 0 = unavailable). This fact decides playback availability
/// — the position value never infers it.
extern "c" fn music_available() -> Int = "ai_passport_music_available"

///|
/// Playback position of the C music transport in microseconds within the
/// current loop iteration. Meaningful only while the transport reports
/// itself available.
extern "c" fn music_position_us() -> Int64 = "ai_passport_music_position_us"

///|
/// Publishes the absolute desired audio output state (volume 0..=100,
/// muted as the C integers 1/0) to the C music transport.
extern "c" fn music_set_output(volume : Int, muted : Int) -> Unit = "ai_passport_music_set_output"

///|
/// Monotonic device frame clock in microseconds from the C clock bridge.
extern "c" fn raw_now_us() -> Int64 = "ai_passport_now_us"
