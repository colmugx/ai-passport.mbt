///|
/// Draws the current scene with placeholder geometry only (sprites and text
/// arrive in later PRs): a soft sky, a mist band, a ground strip along the
/// bottom and the walker as a 12x20 pixel rectangle body fixed near x=32.
/// Darker tufts on the ground march with `scroll` as a placeholder for world
/// motion. Every dimension derives from `canvas.width()` / `canvas.height()`,
/// so the scene renders on any canvas at least walker-sized; out-of-canvas
/// rectangles clip silently.
pub fn State::draw(self : State, canvas~ : @graphics.Canvas) -> Unit {
  let width = canvas.width()
  let height = canvas.height()
  let sky = @core.Color::rgb(r=172, g=208, b=232)
  let mist = @core.Color::rgb(r=224, g=230, b=238)
  let ground = @core.Color::rgb(r=62, g=98, b=58)
  let tuft = @core.Color::rgb(r=44, g=76, b=44)
  let walker = @core.Color::rgb(r=96, g=64, b=48)
  canvas.clear(color=sky)
  // Mist band across the upper third.
  canvas.fill_rect(
    x=0,
    y=height / 3,
    w=width,
    h=(height / 8).max(1),
    color=mist,
  )
  // Ground strip along the bottom.
  let ground_y = height - (height / 5).max(1)
  canvas.fill_rect(x=0, y=ground_y, w=width, h=height - ground_y, color=ground)
  // Placeholder parallax: one darker pixel every 8 columns, marching with
  // the scroll offset.
  for x in 0..<width {
    if (x + self.scroll) % 8 == 0 {
      canvas.pixel(x~, y=ground_y, color=tuft)
    }
  }
  // The walker stands on the ground strip, horizontally fixed near x=32.
  canvas.fill_rect(x=32, y=(ground_y - 20).max(0), w=12, h=20, color=walker)
}
