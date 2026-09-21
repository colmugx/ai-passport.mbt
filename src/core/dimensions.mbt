///|
/// Default logical display width for the current Web and FoloToy Hosts.
///
/// Applications should query `@graphics.display_info()` for Host dimensions.
///
/// # Example
/// ```mbt check
/// test {
///   inspect(@core.LOGICAL_WIDTH, content="240")
/// }
/// ```
pub const LOGICAL_WIDTH : Int = 240

///|
/// Default logical display height for the current Web and FoloToy Hosts.
///
/// Applications should query `@graphics.display_info()` for Host dimensions.
///
/// # Example
/// ```mbt check
/// test {
///   inspect(@core.LOGICAL_HEIGHT, content="320")
/// }
/// ```
pub const LOGICAL_HEIGHT : Int = 320
