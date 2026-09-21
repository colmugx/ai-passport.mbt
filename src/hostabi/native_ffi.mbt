///|
/// Native-target-gated raw device ABI (internal). This file is compiled ONLY
/// for the `native` backend (`moon.pkg` targets gating): the `extern "c"`
/// declarations bind to the C bridge symbols that the device firmware links
/// (see `hosts/folotoy/ai-passport/main/`), so a js or wasm build
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
pub extern "c" fn device_backlight_level() -> Int = "ai_passport_display_backlight_level"

///|
pub extern "c" fn device_set_backlight(level : Int) -> Unit = "ai_passport_display_set_backlight"

///|
/// Raw state-of-charge reading from the device battery bridge: 0..100, or
/// -1 when unavailable (gauge missing, unreadable, or not yet initialized).
/// The integer crosses the boundary unchanged.
extern "c" fn battery_soc() -> Int = "ai_passport_battery_soc"

///|
/// Publishes the absolute desired audio output state (volume 0..=100,
/// muted as the C integers 1/0) to the C sound runtime.
extern "c" fn sound_set_output(volume : Int, muted : Int) -> Unit = "ai_passport_sound_set_output"

///|
pub extern "c" fn sound_play(sound_id : Int, looping : Int) -> Int = "ai_passport_sound_play"

///|
pub extern "c" fn sound_pause(handle : Int) -> Unit = "ai_passport_sound_pause"

///|
pub extern "c" fn sound_resume(handle : Int) -> Unit = "ai_passport_sound_resume"

///|
pub extern "c" fn sound_stop(handle : Int) -> Unit = "ai_passport_sound_stop"

///|
pub extern "c" fn sound_position_us(handle : Int) -> Int64 = "ai_passport_sound_position_us"

///|
/// Monotonic device frame clock in microseconds from the C clock bridge.
extern "c" fn raw_now_us() -> Int64 = "ai_passport_now_us"

///|
pub extern "c" fn capture_start() -> Int = "ai_passport_mic_start"

///|
pub extern "c" fn capture_status() -> Int = "ai_passport_mic_status"

///|
pub extern "c" fn capture_stop() -> Unit = "ai_passport_mic_stop"

///|
#borrow(out)
pub extern "c" fn capture_read(out : FixedArray[Int], capacity : Int) -> Int = "ai_passport_mic_read"

///|
pub extern "c" fn capture_dropped() -> Int = "ai_passport_mic_dropped_samples"

///|
pub extern "c" fn device_power_request(wake_after_ms : Int) -> Int = "ai_passport_power_request"

///|
pub extern "c" fn device_wake_reason() -> Int = "ai_passport_power_wake_reason"
