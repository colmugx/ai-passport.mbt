///|
/// Host panel information. Drawing remains color semantic; a monochrome
/// Host converts colors at presentation, never in application code.
pub(all) struct DisplayInfo {
  width : Int
  height : Int
  monochrome : Bool
  has_backlight : Bool
} derive(Eq, Debug)

///|
/// Queries the active Host's full drawable dimensions and capabilities.
/// Call after Host boot, including from the application's `passport_main`.
pub fn display_info() -> DisplayInfo {
  let level = @display_runtime.backlight_level()
  if level < -1 || level > 100 {
    abort("display Host returned an invalid backlight level: \{level}")
  }
  {
    width: @display_runtime.width(),
    height: @display_runtime.height(),
    monochrome: @display_runtime.monochrome(),
    has_backlight: level >= 0,
  }
}

///|
/// Returns the current light level, or `None` for an unlit panel such as a
/// reflective LCD or e-ink screen.
pub fn backlight_level() -> Int? {
  let level = @display_runtime.backlight_level()
  if level == -1 {
    None
  } else if level < 0 || level > 100 {
    abort("display Host returned an invalid backlight level: \{level}")
  } else {
    Some(level)
  }
}

///|
/// Sets light level 0..100. Returns `false` when the panel has no light;
/// applications can branch on `display_info().has_backlight` first.
pub fn set_backlight(level : Int) -> Bool {
  if level < 0 || level > 100 {
    abort("backlight level must be 0..100")
  }
  if backlight_level() is None {
    return false
  }
  @display_runtime.set_backlight(level)
  true
}
