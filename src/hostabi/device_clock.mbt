///|
/// Monotonic device frame clock in microseconds, read through the Host's C
/// clock bridge. Drives the portable application's fixed-step frame
/// accumulator; unlike the playback position it never wraps, so it is safe
/// as a time base. Consumers compare deltas, never absolute values.
pub fn device_now_us() -> Int64 {
  raw_now_us()
}

///|
/// The legacy frame-global playback clock has no meaning once independent
/// Sound playbacks exist. Keep the old FrameContext field empty until that
/// field is removed in the legacy-model cleanup; callers use
/// `@audio.position(playback)` for the selected playback instead.
pub fn device_playback_position_us() -> Int64? {
  None
}
