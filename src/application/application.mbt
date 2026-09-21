///|
/// The application contract every ai-passport Host runs: the SAME compiled
/// application semantics serve the Web Host and a physical Host. The
/// application package implements this trait for its own state type and
/// exposes one instance through `pub fn passport_main() -> &Application`;
/// the Host entry adapters the CLI generates own every platform detail. The
/// application package must not import Host implementation packages
/// (`hostabi` and below).
pub(open) trait Application {
  /// One host-paced frame tick with the current Host facts. The application
  /// owns its simulation rate — the contract imposes no fixed loop.
  fn update(Self, ctx : FrameContext) -> Unit
  /// One semantic button edge (`Up`, `Down`, `Ok`; press or release). A
  /// Host may deliver a press pulse without a matching release; the
  /// application decides what the edges mean.
  fn button(Self, button : @input.Button, pressed : Bool) -> Unit
  /// One recognized button action. `Press` is delivered immediately;
  /// `Click`, `DoubleClick`, and `LongPress` are mutually exclusive outcomes
  /// for a short/long interaction. Hosts keep each semantic button separate.
  /// Existing applications may omit this callback.
  fn button_event(Self, button : @input.Button, event : @input.ButtonEvent) -> Unit = _
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

///|
impl Application with fn button_event(_self, _button, _event) {
  ()
}
