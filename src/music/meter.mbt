///|
/// Musical meter: `numerator` beats per bar, each beat a 1/`denominator`
/// note (6/8 means six eighth-note beats per bar).
///
/// The v0.1 default meter is 6/8 (`docs/MUSIC.md`), accented on beats 1 and 4.
///
/// # Example
/// ```mbt check
/// test {
///   let meter = Meter::six_eight()
///   debug_inspect((meter.numerator, meter.denominator), content="(6, 8)")
/// }
/// ```
pub(all) struct Meter {
  numerator : Int
  denominator : Int
} derive(Debug)

///|
/// The 6/8 meter, the default meter for v0.1 (`docs/MUSIC.md`).
pub fn Meter::six_eight() -> Meter {
  { numerator: 6, denominator: 8, }
}
