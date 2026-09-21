///|
/// Installs one Host's panel facts and optional illumination control.
pub fn install_display(
  width~ : Int,
  height~ : Int,
  monochrome~ : Bool,
  backlight_level~ : () -> Int,
  set_backlight~ : (Int) -> Unit,
) -> Unit {
  @display_runtime.install(
    @display_runtime.DisplayRuntime::new(
      width~,
      height~,
      monochrome~,
      backlight_level~,
      set_backlight~,
    ),
  )
}
