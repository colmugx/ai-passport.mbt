///|
/// Drawing surface. The internal storage is a private implementation detail
/// (host may keep a full buffer, device may rasterize strip-by-strip) and is
/// never exposed through the public API. Pixels are kept as one 16-bit
/// RGB565 value each (`FixedArray[UInt16]`), which halves the frame memory
/// against an `Int` array on 32-bit targets; colors cross the API boundary
/// exclusively as `@core.Color` values.
///
/// All drawing primitives are clip-safe: coordinates outside the canvas are
/// silently ignored instead of panicking.
pub struct Canvas {
  priv width : Int
  priv height : Int
  priv pixels : FixedArray[UInt16]
}

///|
/// Creates a canvas with the given logical dimensions.
///
/// Both dimensions must be positive; the call aborts when `width <= 0` or
/// `height <= 0`. A fresh canvas is filled with black.
///
/// # Example
/// ```mbt check
/// test {
///   let canvas = @graphics.Canvas::new(width=8, height=8)
///   debug_inspect((canvas.width(), canvas.height()), content="(8, 8)")
/// }
/// ```
pub fn Canvas::new(width~ : Int, height~ : Int) -> Canvas {
  if width <= 0 || height <= 0 {
    abort(
      "Canvas::new: dimensions must be positive, got width=\{width} height=\{height}",
    )
  }
  { width, height, pixels: FixedArray::make(width * height, 0), }
}

///|
/// Creates a canvas matching the v0.1 logical display of 120x160 pixels.
///
/// # Example
/// ```mbt check
/// test {
///   let canvas = @graphics.Canvas::logical()
///   debug_inspect((canvas.width(), canvas.height()), content="(120, 160)")
/// }
/// ```
pub fn Canvas::logical() -> Canvas {
  Canvas::new(width=@core.LOGICAL_WIDTH, height=@core.LOGICAL_HEIGHT)
}

///|
/// Returns the canvas width in logical pixels.
///
/// # Example
/// ```mbt check
/// test {
///   let canvas = @graphics.Canvas::new(width=3, height=5)
///   inspect(canvas.width(), content="3")
/// }
/// ```
pub fn Canvas::width(self : Canvas) -> Int {
  self.width
}

///|
/// Returns the canvas height in logical pixels.
///
/// # Example
/// ```mbt check
/// test {
///   let canvas = @graphics.Canvas::new(width=3, height=5)
///   inspect(canvas.height(), content="5")
/// }
/// ```
pub fn Canvas::height(self : Canvas) -> Int {
  self.height
}
