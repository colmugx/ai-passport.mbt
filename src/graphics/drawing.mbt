///|
/// Fills every pixel of the canvas with `color`.
///
/// # Example
/// ```mbt check
/// test {
///   let canvas = @graphics.Canvas::new(width=2, height=2)
///   canvas.clear(color=@core.Color::rgb(r=255, g=255, b=255))
/// }
/// ```
pub fn Canvas::clear(self : Canvas, color~ : @core.Color) -> Unit {
  let value = color.to_rgb565().to_uint16()
  let pixels = self.pixels
  for i in 0..<pixels.length() {
    pixels[i] = value
  }
}

///|
/// Writes a single pixel at (`x`, `y`).
///
/// Coordinates outside the canvas are silently ignored: the write happens
/// only when `0 <= x < width` and `0 <= y < height`.
///
/// # Example
/// ```mbt check
/// test {
///   let canvas = @graphics.Canvas::new(width=4, height=4)
///   canvas.pixel(x=2, y=1, color=@core.Color::rgb(r=255, g=0, b=0))
///   // Out of bounds: silently ignored, never panics.
///   canvas.pixel(x=4, y=4, color=@core.Color::rgb(r=0, g=255, b=0))
/// }
/// ```
pub fn Canvas::pixel(
  self : Canvas,
  x~ : Int,
  y~ : Int,
  color~ : @core.Color,
) -> Unit {
  if x >= 0 && x < self.width && y >= 0 && y < self.height {
    self.pixels[y * self.width + x] = color.to_rgb565().to_uint16()
  }
}

///|
/// Fills the axis-aligned rectangle `[x, x + w) x [y, y + h)` with `color`,
/// clipped to the canvas bounds.
///
/// Rectangles with `w <= 0` or `h <= 0` draw nothing. A rectangle that
/// extends past any edge writes only its visible part; a rectangle entirely
/// outside the canvas writes nothing. Both calls never panic.
///
/// # Example
/// ```mbt check
/// test {
///   let canvas = @graphics.Canvas::new(width=8, height=8)
///   canvas.fill_rect(x=1, y=2, w=3, h=2, color=@core.Color::rgb(r=0, g=0, b=255))
///   // Extends past the edges: only the visible part is drawn.
///   canvas.fill_rect(
///     x=6,
///     y=6,
///     w=10,
///     h=10,
///     color=@core.Color::rgb(r=255, g=255, b=0),
///   )
/// }
/// ```
pub fn Canvas::fill_rect(
  self : Canvas,
  x~ : Int,
  y~ : Int,
  w~ : Int,
  h~ : Int,
  color~ : @core.Color,
) -> Unit {
  if w <= 0 || h <= 0 {
    return
  }
  let x0 = x.max(0)
  let y0 = y.max(0)
  let x1 = (x + w).min(self.width)
  let y1 = (y + h).min(self.height)
  if x0 >= x1 || y0 >= y1 {
    return
  }
  let value = color.to_rgb565().to_uint16()
  let pixels = self.pixels
  let width = self.width
  for py in y0..<y1 {
    let row = py * width
    for px in x0..<x1 {
      pixels[row + px] = value
    }
  }
}
