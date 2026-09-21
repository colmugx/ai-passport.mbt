///|
/// Primitive full-duplex capture operations supplied by the active Host.
/// Status codes are stable inside the co-versioned SDK/Host release only.
pub struct CaptureRuntime {
  priv start : () -> Int
  priv status : () -> Int
  priv stop : () -> Unit
  priv read : (FixedArray[Int]) -> Int
  priv dropped : () -> Int
}

///|
pub fn CaptureRuntime::new(
  start~ : () -> Int,
  status~ : () -> Int,
  stop~ : () -> Unit,
  read~ : (FixedArray[Int]) -> Int,
  dropped~ : () -> Int,
) -> CaptureRuntime {
  { start, status, stop, read, dropped, }
}

///|
priv struct CaptureSlot {
  mut runtime : CaptureRuntime?
}

///|
let capture_slot : CaptureSlot = { runtime: None, }

///|
pub fn install_capture(runtime : CaptureRuntime) -> Unit {
  if capture_slot.runtime is Some(_) {
    abort("passport capture runtime installed twice")
  }
  capture_slot.runtime = Some(runtime)
}

///|
fn require_capture() -> CaptureRuntime {
  match capture_slot.runtime {
    Some(runtime) => runtime
    None => abort("passport capture runtime used before Host initialization")
  }
}

///|
pub fn capture_start() -> Int {
  (require_capture().start)()
}

///|
pub fn capture_status() -> Int {
  (require_capture().status)()
}

///|
pub fn capture_stop() -> Unit {
  (require_capture().stop)()
}

///|
pub fn capture_read(out : FixedArray[Int]) -> Int {
  (require_capture().read)(out)
}

///|
pub fn capture_dropped() -> Int {
  (require_capture().dropped)()
}
