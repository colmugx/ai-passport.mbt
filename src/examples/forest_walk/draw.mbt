///|
/// Draws the current scene: a soft sky, a mist band, one-frame tree sprites
/// scrolling with `scroll` and wrapping across `canvas width + margin`, a
/// ground strip along the bottom and the four-frame walker sprite fixed
/// near x=32 with its feet on the ground line. The walker pose index is
/// `walker_frame`, advanced by `update` while moving and frozen while
/// paused. Every dimension derives from `canvas.width()` /
/// `canvas.height()`; sprites and rectangles clip silently at the canvas
/// edges.
pub fn State::draw(self : State, canvas~ : @graphics.Canvas) -> Unit {
  let width = canvas.width()
  let height = canvas.height()
  let sky = @core.Color::rgb(r=172, g=208, b=232)
  let mist = @core.Color::rgb(r=224, g=230, b=238)
  let ground = @core.Color::rgb(r=62, g=98, b=58)
  let tuft = @core.Color::rgb(r=44, g=76, b=44)
  let ground_y = height - (height / 5).max(1)
  canvas.clear(color=sky)
  // Mist band across the upper third.
  canvas.fill_rect(
    x=0,
    y=height / 3,
    w=width,
    h=(height / 8).max(1),
    color=mist,
  )
  // Trees march left with the world scroll; each tree re-enters from the
  // right once it has crossed the wrap period (canvas width plus margin).
  let margin = 24
  let period = width + margin
  let trees = self.tree_sheets.length()
  for i in 0..<trees {
    let sheet = self.tree_sheets[i]
    let base = period * i / trees
    let x = ((base - self.scroll) % period + period) % period - margin
    if x + sheet.frame_width() > 0 && x < width {
      canvas.sprite(
        sheet~,
        frame=0,
        x~,
        y=(ground_y - sheet.frame_height() + 2).max(0),
      )
    }
  }
  // Ground strip along the bottom, drawn over the trunk bases so the
  // trees look planted in the grass.
  canvas.fill_rect(x=0, y=ground_y, w=width, h=height - ground_y, color=ground)
  // Placeholder parallax: one darker pixel every 8 columns, marching with
  // the scroll offset.
  for x in 0..<width {
    if (x + self.scroll) % 8 == 0 {
      canvas.pixel(x~, y=ground_y, color=tuft)
    }
  }
  // The walker stands on the ground strip, horizontally fixed near x=32.
  let sheet = self.walker_sheet
  canvas.sprite(
    sheet~,
    frame=self.walker_frame,
    x=32,
    y=(ground_y - sheet.frame_height()).max(0),
  )
}
