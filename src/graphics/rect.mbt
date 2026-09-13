///|
/// 1-pixel rectangle OUTLINE with top-left corner (x, y). `w <= 0 || h <= 0`
/// is a no-op; `w == 1` collapses to a vertical line, `h == 1` to a horizontal
/// line. Clip-safe; interior pixels are not touched.
///
/// # Example
/// ```mbt check
/// test {
///   let canvas = Canvas::new(width=8, height=8)
///   canvas.rect(x=1, y=1, w=4, h=3, color=@core.Color::rgb(r=0, g=0, b=255))
///   // Extends past the edges: only the visible part of the outline is drawn.
///   canvas.rect(x=6, y=6, w=10, h=10, color=@core.Color::rgb(r=255, g=255, b=0))
/// }
/// ```
pub fn Canvas::rect(
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
  // Visible window of the rectangle, clipped exactly like fill_rect.
  let cx0 = x.max(0)
  let cy0 = y.max(0)
  let cx1 = (x + w).min(self.width)
  let cy1 = (y + h).min(self.height)
  if cx0 >= cx1 || cy0 >= cy1 {
    return
  }
  let right = x + w - 1
  let bottom = y + h - 1
  let value = color.to_rgb565().to_uint16()
  let pixels = self.pixels
  let width = self.width
  let height = self.height

  // Top and bottom horizontal edges: only when the row itself is visible.
  if y >= 0 && y < height {
    let row = y * width
    for px in cx0..<cx1 {
      pixels[row + px] = value
    }
  }
  if bottom >= 0 && bottom < height {
    let row = bottom * width
    for px in cx0..<cx1 {
      pixels[row + px] = value
    }
  }
  // Left and right vertical edges: only when the column itself is visible.
  if x >= 0 && x < width {
    for py in cy0..<cy1 {
      pixels[py * width + x] = value
    }
  }
  if right >= 0 && right < width {
    for py in cy0..<cy1 {
      pixels[py * width + right] = value
    }
  }
}
