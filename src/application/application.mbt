///|
/// The application contract every ai-passport Host runs: the SAME compiled
/// application semantics serve the Web Host and a physical Host. The
/// application package implements this trait for its own state type and
/// exposes exactly one instance through a `passport_main` function
/// returning `&Application`; the Host entry adapters the passport CLI
/// generates around that function own every platform detail (Wasm/C ABI
/// exports, bridge construction, wiring). The application package must not
/// import Host implementation packages (`hostabi` and below).
///
/// # Example
/// ```mbt nocheck
/// struct Ticker {
///   mut ticks : Int
/// }
///
/// impl @application.Application for Ticker with fn update(
///   self,
///   _ctx : @application.FrameContext,
/// ) -> Unit {
///   self.ticks = self.ticks + 1
/// }
///
/// impl @application.Application for Ticker with fn button(
///   self,
///   _button : @input.Button,
///   _pressed : Bool,
/// ) -> Unit {
///   let _ = self
/// }
///
/// impl @application.Application for Ticker with fn render(
///   self,
///   _battery_percent : Int?,
/// ) -> @graphics.FrameView {
///   let _ = self
///   @graphics.Canvas::logical().frame_view()
/// }
///
/// impl @application.Application for Ticker with fn audio_output(self) -> @application.AudioOutput? {
///   let _ = self
///   None
/// }
///
/// test {
///   let app : &@application.Application = Ticker::{ ticks: 0, }
///   app.update({
///     now_us: 0L,
///     playback_position_us: None,
///     presentation_lead_us: 0L,
///   })
///   debug_inspect(app.audio_output(), content="None")
/// }
/// ```
pub(open) trait Application {
  /// One host-paced frame tick with the current Host facts. The application
  /// owns its simulation rate — the contract imposes no fixed loop.
  fn update(Self, ctx : FrameContext) -> Unit
  /// One semantic button edge (`Up`, `Down`, `Ok`; press or release). A
  /// Host may deliver a press pulse without a matching release; the
  /// application decides what the edges mean.
  fn button(Self, button : @input.Button, pressed : Bool) -> Unit
  /// Render the logical frame now. `battery_percent` is the Host's
  /// best-effort reading (`None` = unknown). Returns the logical frame to
  /// present.
  fn render(Self, battery_percent : Int?) -> @graphics.FrameView
  /// The application's desired audio output state, or `None` when the
  /// application has none (a no-audio application expresses no fake music
  /// state). Hosts never translate `None` into an invented volume or mute,
  /// and no audio operation is ever performed for it.
  fn audio_output(Self) -> AudioOutput?
}
