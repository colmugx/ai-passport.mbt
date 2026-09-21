///|
pub struct PowerRuntime {
  priv request : (Int) -> Int
  priv wake_reason : () -> Int
}

///|
pub fn PowerRuntime::new(
  request~ : (Int) -> Int,
  wake_reason~ : () -> Int,
) -> PowerRuntime {
  { request, wake_reason, }
}

///|
priv struct PowerSlot {
  mut runtime : PowerRuntime?
}

///|
let power_slot : PowerSlot = { runtime: None, }

///|
pub fn install(runtime : PowerRuntime) -> Unit {
  if power_slot.runtime is Some(_) {
    abort("passport power runtime installed twice")
  }
  power_slot.runtime = Some(runtime)
}

///|
fn require_power() -> PowerRuntime {
  match power_slot.runtime {
    Some(runtime) => runtime
    None => abort("passport power runtime used before Host initialization")
  }
}

///|
pub fn request(wake_after_ms : Int) -> Int {
  (require_power().request)(wake_after_ms)
}

///|
pub fn wake_reason() -> Int {
  (require_power().wake_reason)()
}
