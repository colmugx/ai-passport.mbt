///|
/// Read-only view of a finished `Canvas` frame, handed to display backends.
///
/// `Canvas` deliberately keeps its pixel storage private (AGENTS.md rule 6),
/// but a backend implementing `DisplaySink` must be able to read the drawn
/// frame. `FrameView` is the narrow window for that: it exposes the logical
/// dimensions and row-wise RGB565 copies — never the internal buffer, never
/// mutation, never strip or display-controller concepts. RGB565 is the
/// canonical presentation format, so a web preview and the device LCD see
/// the same quantized colors.
///
/// # Lifetime
///
/// A `FrameView` shares the source canvas's storage and is only guaranteed
/// valid until the source `Canvas` is mutated again. A sink must consume it
/// synchronously inside `present` — copy rows out with `copy_rgb565_row` or
/// push them straight to the panel — and never retain the view. No
/// full-frame snapshot is taken per present.
pub struct FrameView {
  priv width : Int
  priv height : Int
  priv pixels : FixedArray[Int]
}

///|
/// Frame width in logical pixels.
///
/// # Example
/// ```mbt check
/// test {
///   let canvas = Canvas::new(width=8, height=8)
///   inspect(canvas.frame_view().width(), content="8")
/// }
/// ```
pub fn FrameView::width(self : FrameView) -> Int {
  self.width
}

///|
/// Frame height in logical pixels.
///
/// # Example
/// ```mbt check
/// test {
///   let canvas = Canvas::new(width=8, height=8)
///   inspect(canvas.frame_view().height(), content="8")
/// }
/// ```
pub fn FrameView::height(self : FrameView) -> Int {
  self.height
}

///|
/// Copies row `y` of the frame, as RGB565 values, into `out` and returns the
/// number of samples written. Edge behavior is defined, not panicking:
///
/// - `y` outside `0..<height` copies nothing and returns `0`.
/// - `out` shorter than the frame width copies the prefix that fits and
///   returns that count; a backend detects truncation by comparing the
///   return value with `width()`.
/// - `out` longer than the frame width leaves the surplus cells untouched.
///
/// # Example
/// ```mbt check
/// test {
///   let canvas = Canvas::new(width=3, height=2)
///   canvas.fill_rect(x=0, y=0, w=3, h=2, color=@core.Color::rgb(r=255, g=0, b=0))
///   let row : FixedArray[Int] = FixedArray::make(3, 0)
///   let copied = canvas.frame_view().copy_rgb565_row(y=0, out=row)
///   inspect(copied, content="3")
/// }
/// ```
pub fn FrameView::copy_rgb565_row(
  self : FrameView,
  y~ : Int,
  out~ : FixedArray[Int],
) -> Int {
  if y < 0 || y >= self.height {
    return 0
  }
  let n = if out.length() < self.width { out.length() } else { self.width }
  let base = y * self.width
  for i in 0..<n {
    out[i] = self.pixels[base + i]
  }
  n
}

///|
/// Borrows a read-only view of the canvas frame for display backends.
///
/// The view shares the canvas storage (zero copy). It stays valid only until
/// the next mutation of this canvas — see `FrameView` for the lifetime
/// contract.
///
/// # Example
/// ```mbt check
/// test {
///   let canvas = Canvas::logical()
///   let frame = canvas.frame_view()
///   debug_inspect((frame.width(), frame.height()), content="(120, 160)")
/// }
/// ```
pub fn Canvas::frame_view(self : Canvas) -> FrameView {
  { width: self.width, height: self.height, pixels: self.pixels, }
}
