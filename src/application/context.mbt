///|
/// Host facts for one application frame tick. Every field is a generic
/// Host fact; the application alone decides what it means for its own
/// simulation.
pub(all) struct FrameContext {
  /// Monotonic host time in microseconds. Applications must compare deltas,
  /// never absolute values (the same discipline as `@driver.Clock`).
  now_us : Int64
  /// The Host's presentation calibration for playback-position consumers,
  /// in microseconds: how far a position-driven presentation should lead
  /// the reported position on this Host. The Web Host reports `0`; a
  /// physical Host reports its measured hardware lead. The application
  /// receives the fact and must not test Host ids.
  presentation_lead_us : Int64
} derive(Eq, Debug)
