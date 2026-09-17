///|
/// Host probes into the hostabi native test stubs (see
/// `src/hostabi/native_stub.c`): drive the frozen device clocks and read
/// the recorded music-transport output exactly as the device firmware
/// would report them.
extern "c" fn test_set_music_available(available : Int) -> Unit = "ai_passport_test_set_music_available"

///|
extern "c" fn test_set_music_position(position_us : Int64) -> Unit = "ai_passport_test_set_music_position"

///|
extern "c" fn test_set_now_us(now_us : Int64) -> Unit = "ai_passport_test_set_now_us"

///|
extern "c" fn test_last_output_volume() -> Int = "ai_passport_test_last_output_volume"

///|
extern "c" fn test_last_output_muted() -> Int = "ai_passport_test_last_output_muted"

///|
extern "c" fn test_output_set_calls() -> Int = "ai_passport_test_output_set_calls"

///|
/// The device runtime owns one global slot; white-box tests reset it
/// between cases (a second boot without a reset aborts by design, proven
/// by the panic test below).
fn reset_device_slot() -> Unit {
  device_slot.runtime = None
}

///|
struct DeviceApp {
  mut last_ctx : @application.FrameContext?
  mut ok_edges : Int
  mut output : @application.AudioOutput?
  canvas : @graphics.Canvas
}

///|
impl @application.Application for DeviceApp with fn update(
  self,
  ctx : @application.FrameContext,
) -> Unit {
  self.last_ctx = Some(ctx)
}

///|
impl @application.Application for DeviceApp with fn button(
  self,
  button,
  _pressed,
) -> Unit {
  if button is Ok {
    self.ok_edges = self.ok_edges + 1
  }
}

///|
impl @application.Application for DeviceApp with fn render(
  self,
  _battery_percent : Int?,
) -> @graphics.FrameView {
  self.canvas.frame_view()
}

///|
impl @application.Application for DeviceApp with fn audio_output(self) -> @application.AudioOutput? {
  self.output
}

///|
test "the device runtime drives one application through the C ABI shape" {
  reset_device_slot()
  test_set_now_us(9_000_000L)
  test_set_music_available(1)
  test_set_music_position(150_000L)
  let app = DeviceApp::{
    last_ctx: None,
    ok_edges: 0,
    output: Some({ volume: 70, muted: false, }),
    canvas: @graphics.Canvas::logical(),
  }
  device_boot(fn() { app })
  // The transport mirror is seeded with the initial facts, so the first
  // update with unchanged state crosses nothing.
  let calls_before = test_output_set_calls()
  device_update()
  debug_inspect(
    app.last_ctx,
    content=(
      #|Some(
      #|  {
      #|    now_us: 9000000,
      #|    playback_position_us: Some(150000),
      #|    presentation_lead_us: 100000,
      #|  },
      #|)
    ),
  )
  assert_eq(test_output_set_calls(), calls_before)
  // A changed output state mirrors once with the C integer encoding.
  app.output = Some({ volume: 70, muted: true, })
  device_update()
  assert_eq(test_output_set_calls(), calls_before + 1)
  assert_eq(test_last_output_volume(), 70)
  assert_eq(test_last_output_muted(), 1)
  // Draw renders with the device battery reading (stub: unavailable).
  device_draw()
  // A button press pulse becomes one edge pair; unknown codes are dropped.
  device_input(2)
  device_input(7)
  assert_eq(app.ok_edges, 2)
  // C reads the startup output facts through the ABI accessors.
  assert_eq(device_audio_volume(), 70)
  assert_eq(device_audio_muted(), 1)
  // Restore the shared stub state for other tests.
  test_set_music_available(0)
  test_set_music_position(0L)
  test_set_now_us(0L)
}

///|
test "a no-audio device application answers silence, never a default volume" {
  reset_device_slot()
  test_set_now_us(1_000L)
  test_set_music_available(0)
  let app = DeviceApp::{
    last_ctx: None,
    ok_edges: 0,
    output: None,
    canvas: @graphics.Canvas::logical(),
  }
  device_boot(fn() { app })
  let calls_before = test_output_set_calls()
  device_update()
  device_draw()
  debug_inspect(app.last_ctx.unwrap().playback_position_us, content="None")
  assert_eq(test_output_set_calls(), calls_before)
  assert_eq(device_audio_volume(), 0)
  assert_eq(device_audio_muted(), 1)
  test_set_now_us(0L)
}

///|
test "panic device boot twice" {
  reset_device_slot()
  ignore(
    device_boot(fn() {
      DeviceApp::{
        last_ctx: None,
        ok_edges: 0,
        output: None,
        canvas: @graphics.Canvas::logical(),
      }
    }),
  )
  ignore(
    device_boot(fn() {
      DeviceApp::{
        last_ctx: None,
        ok_edges: 0,
        output: None,
        canvas: @graphics.Canvas::logical(),
      }
    }),
  )
}
