///|
/// Logical display width in pixels for v0.1.
///
/// This pins the core contract in `docs/PLAN.md`: apps render against a
/// fixed 120×160 logical display on every backend.
///
/// # Example
/// ```mbt check
/// test {
///   inspect(@core.LOGICAL_WIDTH, content="120")
/// }
/// ```
pub const LOGICAL_WIDTH : Int = 120

///|
/// Logical display height in pixels for v0.1.
///
/// This pins the core contract in `docs/PLAN.md`: apps render against a
/// fixed 120×160 logical display on every backend.
///
/// # Example
/// ```mbt check
/// test {
///   inspect(@core.LOGICAL_HEIGHT, content="160")
/// }
/// ```
pub const LOGICAL_HEIGHT : Int = 160
