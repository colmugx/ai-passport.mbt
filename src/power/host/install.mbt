///|
pub fn install_power(request~ : (Int) -> Int, wake_reason~ : () -> Int) -> Unit {
  @power_runtime.install(
    @power_runtime.PowerRuntime::new(request~, wake_reason~),
  )
}
