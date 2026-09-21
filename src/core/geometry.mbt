///|
/// A point in logical display coordinates.
///
/// # Example
/// ```mbt check
/// test {
///   debug_inspect(@core.Point::{ x: 12, y: 34, }, content="{ x: 12, y: 34 }")
/// }
/// ```
pub(all) struct Point {
  x : Int
  y : Int
} derive(Debug, Eq)

///|
/// Explicitly promotes the derived `Debug` method to a regular method.
pub extend Point with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Explicitly promotes the derived `Eq` methods to regular methods.
pub extend Point with Eq::{not_equal, equal}

///|
/// A width/height pair in logical display coordinates.
///
/// # Example
/// ```mbt check
/// test {
///   debug_inspect(@core.Size::{ w: 120, h: 160, }, content="{ w: 120, h: 160 }")
/// }
/// ```
pub(all) struct Size {
  w : Int
  h : Int
} derive(Debug, Eq)

///|
/// Explicitly promotes the derived `Debug` method to a regular method.
pub extend Size with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Explicitly promotes the derived `Eq` methods to regular methods.
pub extend Size with Eq::{not_equal, equal}
