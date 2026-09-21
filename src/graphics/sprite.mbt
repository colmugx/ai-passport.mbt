///|
/// A grid of sprite frames. Internal storage is private; one RGB565 value
/// per pixel with -1 marking a transparent pixel. Frames are addressed
/// row-major (frame 0 = top-left).
///
/// Storage note: the sheet deliberately keeps `FixedArray[Int]` rather than
/// the canvas's 16-bit `FixedArray[UInt16]` — RGB565 has no spare code point
/// for transparency (every 16-bit pattern is a legal color), so the sentinel
/// needs a value outside `0..=65535`. A magic-color key or a side
/// transparency bitmap would trade correctness or blit efficiency for two
/// bytes per sprite pixel; sprite frames are small, so the wider array is
/// the cheaper trade.
pub(all) struct SpriteSheet {
  priv frame_width : Int
  priv frame_height : Int
  priv pixels : FixedArray[Int]
}

///|
/// Builds a sheet from per-pixel colors; `None` = transparent pixel.
///
/// Frames are addressed row-major: the first `frame_width * frame_height`
/// colors form frame 0, the next block forms frame 1, and so on.
///
/// Aborts if `frame_width <= 0`, `frame_height <= 0`, or `pixels.length()`
/// is zero or not an exact multiple of `frame_width * frame_height`.
///
/// # Example
/// ```mbt check
/// test {
///   let sheet = @graphics.SpriteSheet::from_colors(
///     frame_width=2,
///     frame_height=2,
///     pixels=[
///       Some(@core.Color::rgb(r=255, g=0, b=0)),
///       None,
///       None,
///       Some(@core.Color::rgb(r=0, g=0, b=255)),
///     ],
///   )
///   debug_inspect(
///     (sheet.frame_width(), sheet.frame_height(), sheet.frame_count()),
///     content="(2, 2, 1)",
///   )
/// }
/// ```
pub fn SpriteSheet::from_colors(
  frame_width~ : Int,
  frame_height~ : Int,
  pixels~ : Array[@core.Color?],
) -> SpriteSheet {
  if frame_width <= 0 || frame_height <= 0 {
    abort(
      "SpriteSheet::from_colors: frame dimensions must be positive, got frame_width=\{frame_width} frame_height=\{frame_height}",
    )
  }
  let frame_area = frame_width * frame_height
  if pixels.length() == 0 ||
    frame_area <= 0 ||
    pixels.length() % frame_area != 0 {
    abort(
      "SpriteSheet::from_colors: pixels length must be a nonzero multiple of frame_width * frame_height, got length=\{pixels.length()} frame_width=\{frame_width} frame_height=\{frame_height}",
    )
  }
  let storage : FixedArray[Int] = FixedArray::make(pixels.length(), -1)
  for i in 0..<pixels.length() {
    if pixels[i] is Some(color) {
      storage[i] = color.to_rgb565()
    }
  }
  { frame_width, frame_height, pixels: storage, }
}

///|
/// Returns the frame width in pixels.
///
/// # Example
/// ```mbt check
/// test {
///   let sheet = @graphics.SpriteSheet::from_colors(
///     frame_width=3,
///     frame_height=1,
///     pixels=[None, None, None],
///   )
///   inspect(sheet.frame_width(), content="3")
/// }
/// ```
pub fn SpriteSheet::frame_width(self : SpriteSheet) -> Int {
  self.frame_width
}

///|
/// Returns the frame height in pixels.
///
/// # Example
/// ```mbt check
/// test {
///   let sheet = @graphics.SpriteSheet::from_colors(
///     frame_width=1,
///     frame_height=2,
///     pixels=[None, None],
///   )
///   inspect(sheet.frame_height(), content="2")
/// }
/// ```
pub fn SpriteSheet::frame_height(self : SpriteSheet) -> Int {
  self.frame_height
}

///|
/// Returns the number of frames stored in the sheet.
///
/// # Example
/// ```mbt check
/// test {
///   let sheet = @graphics.SpriteSheet::from_colors(
///     frame_width=1,
///     frame_height=1,
///     pixels=[None, None, None, None],
///   )
///   inspect(sheet.frame_count(), content="4")
/// }
/// ```
pub fn SpriteSheet::frame_count(self : SpriteSheet) -> Int {
  self.pixels.length() / (self.frame_width * self.frame_height)
}

///|
/// Draws sheet frame `frame` with its top-left corner at (`x`, `y`).
///
/// Transparent pixels are skipped, so the existing backdrop is preserved
/// underneath them. The draw is clip-safe: a frame extending past any edge
/// writes only its visible part, and a frame index outside
/// `0 ..< sheet.frame_count()` is a silent no-op. Neither case panics. The
/// draw path performs no allocation.
///
/// # Example
/// ```mbt check
/// test {
///   let sheet = @graphics.SpriteSheet::from_colors(
///     frame_width=1,
///     frame_height=1,
///     pixels=[Some(@core.Color::rgb(r=255, g=0, b=0)), None],
///   )
///   let canvas = @graphics.Canvas::new(width=2, height=1)
///   canvas.sprite(sheet~, frame=0, x=0, y=0)
///   canvas.sprite(sheet~, frame=1, x=1, y=0) // transparent: keeps backdrop
///   canvas.sprite(sheet~, frame=9, x=1, y=0) // out of range: silent no-op
/// }
/// ```
pub fn Canvas::sprite(
  self : Canvas,
  sheet~ : SpriteSheet,
  frame~ : Int,
  x~ : Int,
  y~ : Int,
) -> Unit {
  let frame_width = sheet.frame_width
  let frame_height = sheet.frame_height
  if frame < 0 || frame >= sheet.frame_count() {
    return
  }
  let x0 = x.max(0)
  let y0 = y.max(0)
  let x1 = (x + frame_width).min(self.width)
  let y1 = (y + frame_height).min(self.height)
  if x0 >= x1 || y0 >= y1 {
    return
  }
  let sheet_pixels = sheet.pixels
  let canvas_pixels = self.pixels
  let canvas_width = self.width
  let frame_base = frame * frame_width * frame_height
  for py in y0..<y1 {
    let sheet_row = frame_base + (py - y) * frame_width
    let canvas_row = py * canvas_width
    for px in x0..<x1 {
      let value = sheet_pixels[sheet_row + (px - x)]
      if value != -1 {
        canvas_pixels[canvas_row + px] = value.to_uint16()
      }
    }
  }
}
