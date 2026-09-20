///|
/// Contract-shape proof: a type OUTSIDE this package implements the trait
/// and is consumed through the trait object — exactly the downstream shape
/// the generated Host entries rely on.
struct ProbeApp {
  mut updates : Int
  mut last_now_us : Int64
  mut last_battery : Int?
  mut pressed_ok : Bool?
}

///|
impl @application.Application for ProbeApp with fn update(
  self,
  ctx : @application.FrameContext,
) -> Unit {
  self.updates = self.updates + 1
  self.last_now_us = ctx.now_us
}

///|
impl @application.Application for ProbeApp with fn button(
  self,
  button : @input.Button,
  pressed : Bool,
) -> Unit {
  if button is @input.Ok {
    self.pressed_ok = Some(pressed)
  }
}

///|
impl @application.Application for ProbeApp with fn render(
  self,
  battery_percent : Int?,
) -> @graphics.FrameView {
  self.last_battery = battery_percent
  @graphics.Canvas::logical().frame_view()
}

///|
impl @application.Application for ProbeApp with fn audio_output(self) -> @application.AudioOutput? {
  if self.updates > 0 {
    Some({ volume: 40, muted: false, })
  } else {
    None
  }
}

///|
test "an external type runs the whole contract through the trait object" {
  let app = ProbeApp::{
    updates: 0,
    last_now_us: 0L,
    last_battery: None,
    pressed_ok: None,
  }
  let application : &@application.Application = app
  // No audio state before the first tick: distinct from any volume/mute
  // default, and never a fake music state.
  debug_inspect(application.audio_output(), content="None")
  application.update({ now_us: 1_000_000L, presentation_lead_us: 100_000L, })
  assert_eq(app.updates, 1)
  assert_eq(app.last_now_us, 1_000_000L)
  application.button(@input.Ok, true)
  assert_eq(app.pressed_ok, Some(true))
  let frame = application.render(Some(77))
  assert_eq(frame.width(), @core.LOGICAL_WIDTH)
  assert_eq(frame.height(), @core.LOGICAL_HEIGHT)
  assert_eq(app.last_battery, Some(77))
  debug_inspect(
    application.audio_output(),
    content="Some({ volume: 40, muted: false })",
  )
}

///|
test "FrameContext and AudioOutput are plain data" {
  let ctx : @application.FrameContext = {
    now_us: 5L,
    presentation_lead_us: 0L,
  }
  debug_inspect(ctx, content="{ now_us: 5, presentation_lead_us: 0 }")
  let output : @application.AudioOutput = { volume: 100, muted: true, }
  assert_eq(output, { volume: 100, muted: true, })
}
