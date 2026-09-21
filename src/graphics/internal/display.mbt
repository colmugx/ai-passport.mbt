///|
pub struct DisplayRuntime {
  priv width : Int
  priv height : Int
  priv monochrome : Bool
  priv backlight_level : () -> Int
  priv set_backlight : (Int) -> Unit
}

///|
pub fn DisplayRuntime::new(
  width~ : Int,
  height~ : Int,
  monochrome~ : Bool,
  backlight_level~ : () -> Int,
  set_backlight~ : (Int) -> Unit,
) -> DisplayRuntime {
  if width <= 0 || height <= 0 {
    abort("display Host dimensions must be positive")
  }
  { width, height, monochrome, backlight_level, set_backlight, }
}

///|
priv struct DisplaySlot {
  mut runtime : DisplayRuntime?
}

///|
let display_slot : DisplaySlot = { runtime: None, }

///|
pub fn install(runtime : DisplayRuntime) -> Unit {
  if display_slot.runtime is Some(_) {
    abort("passport display runtime installed twice")
  }
  display_slot.runtime = Some(runtime)
}

///|
fn require_display() -> DisplayRuntime {
  match display_slot.runtime {
    Some(runtime) => runtime
    None => abort("passport display queried before Host initialization")
  }
}

///|
pub fn width() -> Int {
  require_display().width
}

///|
pub fn height() -> Int {
  require_display().height
}

///|
pub fn monochrome() -> Bool {
  require_display().monochrome
}

///|
pub fn backlight_level() -> Int {
  (require_display().backlight_level)()
}

///|
pub fn set_backlight(level : Int) -> Unit {
  (require_display().set_backlight)(level)
}
