///|
/// One frame tick (exported as `passport_frame`), in the frozen order:
/// advance the clock, apply the input edges, refresh the battery, draw the
/// deterministic frame, stream the frozen PCM square wave, present the
/// canvas frame through the bridge display sink (marks the framebuffer
/// dirty), and finally clear the input latches at the frame boundary.
pub fn passport_frame(now_us : Int64) -> Unit {
  state.bridge.advance(now_us)
  apply_input()
  state.battery.refresh()
  draw_frame()
  push_pcm()
  let sink : &@driver.DisplaySink = state.bridge
  sink.present(frame=state.canvas.frame_view())
  state.input.advance()
  state.frame += 1
}

///|
/// Consumes the current-frame input edges per the frozen contract: Up moves
/// the selection row up (floor 0), Down moves it down (cap 9), and Ok
/// toggles mute, mirroring the new flag to the host with `host_set_muted`.
/// Edges are latched by `InputState::press` since the previous
/// `InputState::advance`, so each press counts exactly once.
fn apply_input() -> Unit {
  if state.input.just_pressed(Up) && state.sel > 0 {
    state.sel -= 1
  }
  if state.input.just_pressed(Down) && state.sel < SEL_MAX {
    state.sel += 1
  }
  if state.input.just_pressed(Ok) {
    state.muted = !state.muted
    @hostabi.host_set_muted(if state.muted { 1 } else { 0 })
  }
}

///|
/// Draws the frozen deterministic frame on the logical canvas. Draw order is
/// fixed so overlapping regions resolve exactly as the contract asserts:
/// the selection row wins over the volume bar, the volume bar wins over the
/// mute block, and pixel (8,8) is never touched by any primitive. `now_us`
/// is never drawn — the frame depends only on `frame`, `sel`, `muted` and
/// the battery reading.
fn draw_frame() -> Unit {
  let canvas = state.canvas
  canvas.clear(color=@core.Color::rgb(r=0, g=0, b=0))
  // 8x8 frame-counter block at (0,0): red/green/blue/white cycling on N % 4
  // (RGB565 0xF800 / 0x07E0 / 0x001F / 0xFFFF).
  let block = match state.frame % 4 {
    0 => @core.Color::rgb(r=255, g=0, b=0)
    1 => @core.Color::rgb(r=0, g=255, b=0)
    2 => @core.Color::rgb(r=0, g=0, b=255)
    _ => @core.Color::rgb(r=255, g=255, b=255)
  }
  canvas.fill_rect(x=0, y=0, w=8, h=8, color=block)
  // Mute flag block at (112,0)-(119,7): white when muted, cyan when not.
  let mute = if state.muted {
    @core.Color::rgb(r=255, g=255, b=255)
  } else {
    @core.Color::rgb(r=0, g=255, b=255)
  }
  canvas.fill_rect(x=112, y=0, w=8, h=8, color=mute)
  // Volume bar in columns 118..119, rows 0..(160*70/100 - 1): 0x07E0 green.
  canvas.fill_rect(
    x=118,
    y=0,
    w=2,
    h=160 * state.volume / 100,
    color=@core.Color::rgb(r=0, g=255, b=0),
  )
  // Full-width 1px selection row at y = 20 + sel*8: 0xFFE0 yellow.
  canvas.fill_rect(
    x=0,
    y=20 + state.sel * 8,
    w=120,
    h=1,
    color=@core.Color::rgb(r=255, g=255, b=0),
  )
  // Battery percent text at (4,150) in white; the region stays black when
  // the source reports no reading.
  match state.battery.percent() {
    Some(p) =>
      canvas.text(
        text="\{p}%",
        x=4,
        y=150,
        color=@core.Color::rgb(r=255, g=255, b=255),
      )
    None => ()
  }
}

///|
/// Refills the reused PCM chunk with the frozen integer square wave
/// `sample(n) = ((n >> 4) & 1) == 1 ? -4000 : 4000` (500 Hz at 16000 Hz,
/// amplitude 4000 PCM16) starting at the global sample counter, advances the
/// counter by 266, and pushes the chunk through the bridge `PcmSink`, which
/// stages it into linear memory and hands it to `host_pcm_write`.
fn push_pcm() -> Unit {
  let pcm = state.pcm
  for i in 0..<PCM_CHUNK {
    let n = state.sample_counter + i
    pcm[i] = if ((n >> 4) & 1) == 1 { -4000 } else { 4000 }
  }
  state.sample_counter += PCM_CHUNK
  let sink : &@audio.PcmSink = state.bridge
  sink.write(samples=pcm)
}
