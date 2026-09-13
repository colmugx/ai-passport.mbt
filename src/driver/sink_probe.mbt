///|
/// Test double for `DisplaySink`, also a reference for backend tests in the
/// template repo: records how many times `present` was called and the
/// dimensions of the last frame, read at `present` time.
///
/// It deliberately does NOT retain frame views — a view is valid only until
/// the source canvas is mutated again, so only the width/height observed at
/// flush time are recorded.
///
/// # Example
/// ```mbt check
/// test {
///   let probe = SinkProbe::new()
///   let sink : &DisplaySink = probe
///   sink.present(frame=@graphics.Canvas::new(width=64, height=80).frame_view())
///   inspect(probe.calls(), content="1")
///   inspect(probe.last_width(), content="64")
///   inspect(probe.last_height(), content="80")
/// }
/// ```
pub struct SinkProbe {
  priv mut calls : Int
  priv mut last_width : Int
  priv mut last_height : Int
}

///|
/// Creates an empty probe: zero recorded calls and no recorded dimensions
/// (`last_width`/`last_height` start at `0`).
pub fn SinkProbe::new() -> SinkProbe {
  { calls: 0, last_width: 0, last_height: 0, }
}

///|
/// Number of `present` calls recorded so far.
pub fn SinkProbe::calls(self : SinkProbe) -> Int {
  self.calls
}

///|
/// Width of the most recently presented frame, or `0` before the first
/// call.
pub fn SinkProbe::last_width(self : SinkProbe) -> Int {
  self.last_width
}

///|
/// Height of the most recently presented frame, or `0` before the first
/// call.
pub fn SinkProbe::last_height(self : SinkProbe) -> Int {
  self.last_height
}

///|
/// Records one presentation: bumps the call counter and snapshots the
/// frame dimensions at flush time. The view is neither retained nor used
/// after `present` returns.
pub impl DisplaySink for SinkProbe with fn present(
  self,
  frame~ : @graphics.FrameView,
) -> Unit {
  self.calls += 1
  self.last_width = frame.width()
  self.last_height = frame.height()
}
