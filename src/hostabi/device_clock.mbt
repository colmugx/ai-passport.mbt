///|
/// Monotonic device frame clock in microseconds, read through the Host's C
/// clock bridge. Drives the portable application's fixed-step frame
/// accumulator; unlike the playback position it never wraps, so it is safe
/// as a time base. Consumers compare deltas, never absolute values.
pub fn device_now_us() -> Int64 {
  raw_now_us()
}

///|
/// Live device playback position in microseconds within the current loop
/// iteration for the portable App: `Some(position)` — INCLUDING exactly 0
/// at the track start and at the PCM loop boundary — when the transport is
/// running, `None` when music is unavailable. Handed straight to
/// `App::advance` as its playback Option; the App owns the loop wrap,
/// presentation lead and fallback semantics. The C transport's availability
/// fact decides the Option — the position value never infers it.
pub fn device_playback_position_us() -> Int64? {
  if music_available() == 1 {
    Some(music_position_us())
  } else {
    None
  }
}
