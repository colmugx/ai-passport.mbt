///|
/// Installs one Host's input channel beside the output channel.
pub fn install_capture(
  start~ : () -> Int,
  status~ : () -> Int,
  stop~ : () -> Unit,
  read~ : (FixedArray[Int]) -> Int,
  dropped~ : () -> Int,
) -> Unit {
  @sound_runtime.install_capture(
    @sound_runtime.CaptureRuntime::new(start~, status~, stop~, read~, dropped~),
  )
}
