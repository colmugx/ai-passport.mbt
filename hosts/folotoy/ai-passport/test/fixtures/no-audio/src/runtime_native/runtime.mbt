///|
/// No-audio device entry: the smallest valid FoloToy application. The
/// project contract declares no assets (no `pcmLoop`), so this scene wires
/// no audio mirror at all — the firmware embeds no music and the C host
/// runs silent while the display, clock and button ABI stay connected. This
/// package exports exactly the eight ABI symbols `app_main` calls and owns
/// no other logic.
priv struct Scene {
  canvas : @graphics.Canvas
  sink : @hostabi.DeviceDisplaySink
}

///|
priv struct SceneSlot {
  mut scene : Scene?
}

///|
let scene_slot : SceneSlot = { scene: None, }

///|
fn require_scene() -> Scene {
  match scene_slot.scene {
    Some(scene) => scene
    None => abort("no-audio fixture scene used before initialization")
  }
}

///|
/// C calls this symbol from app_main to prove MoonBit code is linked and
/// run.
#export_name("ai_passport_mbt_probe")
pub fn probe() -> Int {
  0xA100 | 0x7E
}

///|
#export_name("ai_passport_mbt_app_init")
pub fn app_init() -> Unit {
  if scene_slot.scene is Some(_) {
    abort("no-audio fixture scene initialized twice")
  }
  scene_slot.scene = Some({
    canvas: @graphics.Canvas::logical(),
    sink: @hostabi.DeviceDisplaySink::new(),
  })
}

///|
/// One C-paced frame tick of a static scene: nothing advances.
#export_name("ai_passport_mbt_app_update")
pub fn app_update() -> Unit {
  ()
}

///|
#export_name("ai_passport_mbt_app_draw")
pub fn app_draw() -> Unit {
  let scene = require_scene()
  scene.canvas.clear(color=@core.Color::rgb(r=0, g=0, b=0))
  scene.canvas.fill_rect(
    x=0,
    y=80,
    w=120,
    h=2,
    color=@core.Color::rgb(r=255, g=255, b=255),
  )
}

///|
#export_name("ai_passport_mbt_app_present")
pub fn app_present() -> Unit {
  let scene = require_scene()
  @driver.DisplaySink::present(scene.sink, frame=scene.canvas.frame_view())
}

///|
/// One raw physical press from the C button bridge. The static scene keeps
/// no input state, so the decoded button is dropped.
#export_name("ai_passport_mbt_input_press")
pub fn input_press(_code : Int) -> Unit {
  ()
}

///|
/// Startup output facts C reads before starting the music transport. This
/// application has no audio state; with no embedded music the transport
/// never starts, so constants are the honest answer.
#export_name("ai_passport_mbt_audio_volume")
pub fn audio_volume() -> Int {
  80
}

///|
#export_name("ai_passport_mbt_audio_muted")
pub fn audio_muted() -> Int {
  0
}
