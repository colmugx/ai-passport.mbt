///|
/// Why the application last resumed from an explicit sleep request.
pub(all) enum WakeReason {
  Button
  Timer
  Other
} derive(Eq, Debug)

///|
fn request(wake_after_ms : Int) -> Bool {
  match @power_runtime.request(wake_after_ms) {
    0 => false
    1 => true
    code => abort("power Host returned an invalid request result: \{code}")
  }
}

///|
/// Requests low-power sleep after the current frame. The Host wakes on a
/// semantic button; `false` means a request is already pending. Capture is
/// stopped before sleep. Playback position is preserved while suspended.
pub fn request_sleep() -> Bool {
  request(-1)
}

///|
/// Also wakes after the given delay, in milliseconds, if no button is used.
/// The delay must be 1..86,400,000 (one day).
pub fn request_timed_sleep(wake_after_ms : Int) -> Bool {
  if wake_after_ms <= 0 || wake_after_ms > 86_400_000 {
    abort("timed sleep duration must be 1..86400000 ms")
  }
  request(wake_after_ms)
}

///|
/// Returns `None` until the first completed sleep, then the most recent
/// cause. A new accepted request clears the previous cause.
pub fn wake_reason() -> WakeReason? {
  match @power_runtime.wake_reason() {
    0 => None
    1 => Some(Button)
    2 => Some(Timer)
    3 => Some(Other)
    code => abort("power Host returned an invalid wake reason: \{code}")
  }
}
