///|
/// A point in logical display coordinates.
///
/// # Example
/// ```mbt check
/// test {
///   debug_inspect(Point::{ x: 12, y: 34, }, content="{ x: 12, y: 34 }")
/// }
/// ```
pub(all) struct Point {
  x : Int
  y : Int
} derive(Debug, Eq)

///|
/// A width/height pair in logical display coordinates.
///
/// # Example
/// ```mbt check
/// test {
///   debug_inspect(Size::{ w: 120, h: 160, }, content="{ w: 120, h: 160 }")
/// }
/// ```
pub(all) struct Size {
  w : Int
  h : Int
} derive(Debug, Eq)
