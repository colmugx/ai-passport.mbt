///|
/// The microphone channel always yields signed PCM16 mono samples at 16 kHz.
/// A Host may be unable to supply capture, or may need asynchronous permission.
pub const CAPTURE_SAMPLE_RATE_HZ : Int = 16_000

///|
pub(all) enum CaptureStatus {
  Unavailable
  Idle
  Requesting
  Recording
  Denied
  Failed
} derive(Debug, Eq)

///|
pub extend CaptureStatus with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CaptureStatus with Eq::{not_equal, equal}

///|
fn decode_capture_status(code : Int) -> CaptureStatus {
  match code {
    0 => Unavailable
    1 => Idle
    2 => Requesting
    3 => Recording
    4 => Denied
    5 => Failed
    _ => abort("capture Host returned an invalid status code: \{code}")
  }
}

///|
/// Requests capture. On Web this may return `Requesting` while the browser
/// asks for microphone permission; poll `capture_status` before reading.
/// `Unavailable`, `Denied`, and `Failed` remain explicit results.
pub fn capture_start() -> CaptureStatus {
  decode_capture_status(@sound_runtime.capture_start())
}

///|
pub fn capture_status() -> CaptureStatus {
  decode_capture_status(@sound_runtime.capture_status())
}

///|
/// Stops capture and drops unread samples. Calling while idle is harmless.
pub fn capture_stop() -> Unit {
  @sound_runtime.capture_stop()
}

///|
/// Reads at most `out.length()` signed PCM16 samples, oldest first. Returns
/// zero when no samples are ready. Reading outside `Recording` is an error;
/// callers must check `capture_status`. The destination must be nonempty.
pub fn capture_read(out : FixedArray[Int]) -> Int {
  if out.length() == 0 {
    abort("capture_read requires a nonempty destination")
  }
  if capture_status() != Recording {
    abort("capture_read requires Recording status")
  }
  let count = @sound_runtime.capture_read(out)
  if count < 0 || count > out.length() {
    abort("capture Host returned an invalid sample count: \{count}")
  }
  count
}

///|
/// Samples discarded because the Host's bounded capture queue filled.
/// Resets to zero when a new capture session starts.
pub fn capture_dropped_samples() -> Int {
  let count = @sound_runtime.capture_dropped()
  if count < 0 {
    abort("capture Host returned a negative drop count")
  }
  count
}
