///|
/// Blackbox proof of the SDK Web runtime against a fake application and
/// injected host operations: host facts flow in, audio deltas flow out,
/// presentation crosses the bridge, and the no-audio application never
/// invents output state.
struct FakeApp {
  updates : Array[@application.FrameContext]
  buttons : Array[@input.Button]
  events : Array[(@input.Button, @input.ButtonEvent)]
  mut battery_seen : Int?
  mut output : @application.AudioOutput?
  canvas : @graphics.Canvas
}

///|
fn FakeApp::make() -> FakeApp {
  {
    updates: [],
    buttons: [],
    events: [],
    battery_seen: None,
    output: None,
    canvas: @graphics.Canvas::logical(),
  }
}

///|
impl @application.Application for FakeApp with fn update(
  self,
  ctx : @application.FrameContext,
) -> Unit {
  self.updates.push(ctx)
}

///|
impl @application.Application for FakeApp with fn button(
  self,
  button : @input.Button,
  _pressed : Bool,
) -> Unit {
  self.buttons.push(button)
}

///|
impl @application.Application for FakeApp with fn button_event(
  self,
  button : @input.Button,
  event : @input.ButtonEvent,
) -> Unit {
  self.events.push((button, event))
}

///|
impl @application.Application for FakeApp with fn render(
  self,
  battery_percent : Int?,
) -> @graphics.FrameView {
  self.battery_seen = battery_percent
  self.canvas.frame_view()
}

///|
impl @application.Application for FakeApp with fn audio_output(self) -> @application.AudioOutput? {
  self.output
}

///|
struct HostCalls {
  volumes : Array[Int]
  muted : Array[Bool]
  pixels : Array[Int]
}

///|
fn make_bridge(
  app~ : FakeApp,
  calls~ : HostCalls,
  battery~ : Int,
) -> @hostabi.HostBridge {
  let _ = app
  @hostabi.HostBridge::new(
    store_u16=fn(_addr : Int, value : Int) { calls.pixels.push(value) },
    battery_percent=fn() { battery },
  )
}

///|
fn make_runtime(
  app~ : FakeApp,
  calls~ : HostCalls,
  battery? : Int = 55,
) -> @runtime.WebRuntime {
  @runtime.WebRuntime::new(
    app~,
    bridge=make_bridge(app~, calls~, battery~),
    set_volume=fn(volume : Int) { calls.volumes.push(volume) },
    set_muted=fn(muted : Bool) { calls.muted.push(muted) },
  )
}

///|
test "one frame delivers host facts, battery, presentation, and dirty state" {
  let app = FakeApp::make()
  let calls = HostCalls::{ volumes: [], muted: [], pixels: [], }
  let runtime = make_runtime(app~, calls~, battery=90)
  runtime.frame(1_000_000L)
  debug_inspect(
    app.updates,
    content="[{ now_us: 1000000, presentation_lead_us: 0 }]",
  )
  assert_eq(app.battery_seen, Some(90))
  // Presenting wrote framebuffer pixels and marked the frame dirty.
  assert_true(calls.pixels.length() > 0)
  assert_eq(runtime.frame_dirty(), 1)
  runtime.frame_consume()
  assert_eq(runtime.frame_dirty(), 0)
}

///|
test "input decodes wire codes and ignores unknown ones" {
  let app = FakeApp::make()
  let calls = HostCalls::{ volumes: [], muted: [], pixels: [], }
  let runtime = make_runtime(app~, calls~)
  runtime.input(0, 1)
  runtime.input(1, 1)
  runtime.input(2, 1)
  runtime.input(9, 1)
  runtime.frame(1L)
  debug_inspect(app.buttons, content="[Up, Down, Ok]")
  debug_inspect(app.events, content="[(Up, Press), (Down, Press), (Ok, Press)]")
}

///|
test "an application with audio state mirrors only deltas" {
  let app = FakeApp::make()
  app.output = Some({ volume: 80, muted: false, })
  let calls = HostCalls::{ volumes: [], muted: [], pixels: [], }
  let runtime = make_runtime(app~, calls~)
  // Startup mirrors the initial state exactly once.
  runtime.start()
  debug_inspect(calls.volumes, content="[80]")
  debug_inspect(calls.muted, content="[false]")
  // Frames with unchanged state cross nothing.
  runtime.frame(1L)
  debug_inspect(calls.volumes, content="[80]")
  // A volume change crosses once; repeating it crosses nothing.
  app.output = Some({ volume: 30, muted: false, })
  runtime.frame(2L)
  debug_inspect(calls.volumes, content="[80, 30]")
  runtime.frame(3L)
  debug_inspect(calls.volumes, content="[80, 30]")
  // Muting crosses the muted import while the volume import stays quiet.
  app.output = Some({ volume: 30, muted: true, })
  runtime.frame(4L)
  debug_inspect(calls.muted, content="[false, true]")
  debug_inspect(calls.volumes, content="[80, 30]")
}

///|
test "a no-audio application never invents output state" {
  let app = FakeApp::make()
  let calls = HostCalls::{ volumes: [], muted: [], pixels: [], }
  let runtime = make_runtime(app~, calls~)
  runtime.start()
  runtime.frame(1L)
  runtime.frame(2L)
  runtime.input(2, 1)
  runtime.frame(3L)
  assert_eq(calls.volumes.length(), 0)
  assert_eq(calls.muted.length(), 0)
  assert_eq(app.buttons.length(), 1)
}
