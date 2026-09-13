///|
/// Frame flush contract. The backend decides how a fully drawn logical frame
/// reaches the panel — a full buffer on the host, RGB565 strips on the
/// device — and this trait is the ONLY thing app-facing code needs
/// (AGENTS.md rule 6: strip rendering never leaks into public APIs; rule 9:
/// backend glue stays thin and replaceable).
///
/// `present` receives a read-only `@graphics.FrameView` of the fully drawn
/// canvas (120×160 logical per docs/DRIVER.md). The view shares the canvas
/// storage: it is valid only until the source canvas is mutated again, so
/// implementations must consume it synchronously — copy rows out with
/// `copy_rgb565_row` (or push them straight to the panel) and never retain
/// the view. The trait is declared `pub(open)` so each backend implements it
/// outside this package; app-facing code only consumes `&DisplaySink` values.
///
/// Verified implementation form (one `pub impl` per method; the `pub` makes
/// the impl visible outside the implementing package's main unit):
///
/// ```mbt nocheck
/// pub impl DisplaySink for MySink with fn present(
///   self,
///   frame~ : @graphics.FrameView,
/// ) -> Unit {
///   ...
/// }
/// ```
///
/// # Example
/// ```mbt check
/// test {
///   let probe = SinkProbe::new()
///   let sink : &DisplaySink = probe
///   sink.present(frame=@graphics.Canvas::logical().frame_view())
///   inspect(probe.calls(), content="1")
/// }
/// ```
pub(open) trait DisplaySink {
  fn present(Self, frame~ : @graphics.FrameView) -> Unit
}
