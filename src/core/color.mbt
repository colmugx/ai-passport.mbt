///|
/// An RGB color with 8-bit components.
///
/// Each component is an integer in `0..=255`. Use [Color::rgb] to build a
/// color with automatic clamping; direct construction is allowed but leaves
/// staying in range to the caller.
pub(all) struct Color {
  r : Int
  g : Int
  b : Int
} derive(Debug, Eq)

///|
/// Explicitly promotes the derived `Debug` method to a regular method.
pub extend Color with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Explicitly promotes the derived `Eq` methods to regular methods.
pub extend Color with Eq::{not_equal, equal}

///|
/// Clamps one color component into `0..=255`.
fn clamp_component(v : Int) -> Int {
  if v < 0 {
    0
  } else if v > 255 {
    255
  } else {
    v
  }
}

///|
/// Builds a color from red, green, and blue components.
///
/// Each component is clamped into `0..=255`, so out-of-range values saturate
/// at the ends of the range instead of wrapping.
///
/// # Example
/// ```mbt check
/// test {
///   debug_inspect(
///     @core.Color::rgb(r=250, g=-1, b=300),
///     content="{ r: 250, g: 0, b: 255 }",
///   )
/// }
/// ```
pub fn Color::rgb(r~ : Int, g~ : Int, b~ : Int) -> Color {
  { r: clamp_component(r), g: clamp_component(g), b: clamp_component(b), }
}

///|
/// Converts to the display's native 16-bit RGB565 color encoding:
/// `(r5 << 11) | (g6 << 5) | b5`, with `r` quantized to 5 bits, `g` to 6
/// bits, and `b` to 5 bits.
///
/// Components are expected to be in `0..=255` (as produced by [Color::rgb]).
///
/// # Example
/// ```mbt check
/// test {
///   inspect(@core.Color::rgb(r=255, g=0, b=0).to_rgb565(), content="63488")
/// }
/// ```
pub fn Color::to_rgb565(self : Color) -> Int {
  let r5 = self.r >> 3
  let g6 = self.g >> 2
  let b5 = self.b >> 3
  (r5 << 11) | (g6 << 5) | b5
}
