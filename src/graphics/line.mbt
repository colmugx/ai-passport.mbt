///|
/// Bresenham line from (x0, y0) to (x1, y1). Per-pixel bounds check —
/// allocation-free and clip-safe; endpoints may lie fully offscreen; drawing
/// (x0,y0)->(x1,y1) and (x1,y1)->(x0,y0) produce identical pixels.
///
/// # Example
/// ```mbt check
/// test {
///   let canvas = Canvas::new(width=8, height=8)
///   canvas.line(x0=0, y0=0, x1=7, y1=4, color=@core.Color::rgb(r=255, g=0, b=0))
///   // Endpoints may lie offscreen: only the visible part is drawn.
///   canvas.line(x0=-3, y0=6, x1=12, y1=2, color=@core.Color::rgb(r=0, g=255, b=0))
/// }
/// ```
pub fn Canvas::line(
  self : Canvas,
  x0~ : Int,
  y0~ : Int,
  x1~ : Int,
  y1~ : Int,
  color~ : @core.Color,
) -> Unit {
  // Run Bresenham over a canonical endpoint order (lexicographically smaller
  // endpoint first) so a segment and its reverse pick the very same pixels.
  let (ax, ay, bx, by) = if x0 < x1 || (x0 == x1 && y0 <= y1) {
    (x0, y0, x1, y1)
  } else {
    (x1, y1, x0, y0)
  }
  let value = color.to_rgb565().to_uint16()
  let pixels = self.pixels
  let width = self.width
  let height = self.height
  let dx = bx - ax
  let dy = -(by - ay).abs()
  let sx = if ax < bx { 1 } else { -1 }
  let sy = if ay < by { 1 } else { -1 }
  let mut err = dx + dy
  let mut x = ax
  let mut y = ay
  for ;; {
    if x >= 0 && x < width && y >= 0 && y < height {
      pixels[y * width + x] = value
    }
    let e2 = err * 2
    if e2 >= dy {
      if x == bx {
        break
      }
      err += dy
      x += sx
    }
    if e2 <= dx {
      if y == by {
        break
      }
      err += dx
      y += sy
    }
  }
}
