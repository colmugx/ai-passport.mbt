///|
/// An axis-aligned rectangle in logical display coordinates.
///
/// A rectangle is *empty* when `w <= 0` or `h <= 0`; rectangles are never
/// normalized, so negative sizes simply mean empty. A non-empty rectangle
/// covers `[x, x + w) × [y, y + h)`: its left and top edges are inclusive,
/// its right and bottom edges exclusive.
pub(all) struct Rect {
  x : Int
  y : Int
  w : Int
  h : Int
} derive(Debug, Eq)

///|
/// Returns `true` when the rectangle is empty (`w <= 0` or `h <= 0`).
fn Rect::is_empty(self : Rect) -> Bool {
  self.w <= 0 || self.h <= 0
}

///|
/// Returns `true` when the point (`x`, `y`) lies inside the rectangle.
///
/// The left and top edges are inclusive; the right and bottom edges are
/// exclusive. An empty rectangle contains nothing.
///
/// # Example
/// ```mbt check
/// test {
///   let r : Rect = { x: 0, y: 0, w: 10, h: 10, }
///   inspect(r.contains(x=0, y=0), content="true")
///   inspect(r.contains(x=9, y=9), content="true")
///   inspect(r.contains(x=10, y=5), content="false")
/// }
/// ```
pub fn Rect::contains(self : Rect, x~ : Int, y~ : Int) -> Bool {
  !self.is_empty() &&
  x >= self.x &&
  x < self.x + self.w &&
  y >= self.y &&
  y < self.y + self.h
}

///|
/// Returns `true` when the two rectangles overlap with positive area.
///
/// Rectangles that merely touch along an edge do not intersect, and an
/// empty rectangle intersects nothing.
///
/// # Example
/// ```mbt check
/// test {
///   let a : Rect = { x: 0, y: 0, w: 10, h: 10, }
///   let b : Rect = { x: 10, y: 0, w: 5, h: 5, }
///   inspect(a.intersects(other=b), content="false")
/// }
/// ```
pub fn Rect::intersects(self : Rect, other~ : Rect) -> Bool {
  !self.is_empty() &&
  !other.is_empty() &&
  self.x < other.x + other.w &&
  other.x < self.x + self.w &&
  self.y < other.y + other.h &&
  other.y < self.y + self.h
}

///|
/// Returns the overlapping rectangle, or `None` when there is no overlap.
///
/// The result is `None` when either rectangle is empty or when the overlap
/// would have zero area (disjoint rectangles, or rectangles that merely
/// touch along an edge).
///
/// # Example
/// ```mbt check
/// test {
///   let a : Rect = { x: 0, y: 0, w: 10, h: 10, }
///   let b : Rect = { x: 5, y: 5, w: 10, h: 10, }
///   debug_inspect(
///     a.intersection(other=b),
///     content="Some({ x: 5, y: 5, w: 5, h: 5 })",
///   )
/// }
/// ```
pub fn Rect::intersection(self : Rect, other~ : Rect) -> Rect? {
  if self.is_empty() || other.is_empty() {
    None
  } else {
    let x1 = self.x.max(other.x)
    let y1 = self.y.max(other.y)
    let x2 = (self.x + self.w).min(other.x + other.w)
    let y2 = (self.y + self.h).min(other.y + other.h)
    if x1 < x2 && y1 < y2 {
      Some({ x: x1, y: y1, w: x2 - x1, h: y2 - y1, })
    } else {
      None
    }
  }
}
