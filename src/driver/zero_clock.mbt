///|
/// Trivial `Clock` for tests and as a reference implementation:
/// `monotonic_ms` always returns `0` and `sleep_ms` is a no-op.
///
/// The struct has no observable state; the only constructor is
/// `ZeroClock::new`, so external code can name the type but never construct
/// it by hand.
///
/// # Example
/// ```mbt check
/// test {
///   let clock = ZeroClock::new()
///   clock.sleep_ms(ms=1000)
///   inspect(clock.monotonic_ms(), content="0")
/// }
/// ```
pub struct ZeroClock {
  priv _unit : Unit
}

///|
/// Creates the zero clock. All instances are equivalent: `monotonic_ms` is
/// constantly `0` and `sleep_ms` does nothing.
///
/// # Example
/// ```mbt check
/// test {
///   let _ : ZeroClock = ZeroClock::new()
/// }
/// ```
pub fn ZeroClock::new() -> ZeroClock {
  { _unit: (), }
}

///|
/// Always returns `0`, regardless of how much (virtual) time passed.
pub impl Clock for ZeroClock with fn monotonic_ms(self) -> Int {
  let _ = self
  0
}

///|
/// No-op. Never blocks and never panics, for any `ms` value, including `0`
/// and values far larger than any frame budget.
pub impl Clock for ZeroClock with fn sleep_ms(self, ms~ : Int) -> Unit {
  let _ = self
  let _ = ms
}
