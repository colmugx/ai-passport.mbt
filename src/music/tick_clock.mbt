///|
/// Deterministic integer bridge from audio samples to eighth-note ticks.
///
/// One eighth note lasts `60 / (dotted_quarter_bpm * 3)` seconds, which is
/// `sample_rate * 60 / (dotted_quarter_bpm * 3)` samples; the fractional
/// remainder is carried exactly, Bresenham-style. No floats anywhere.
///
/// # Example
/// ```mbt check
/// test {
///   let clock = TickClock::new(sample_rate=16000, dotted_quarter_bpm=76)
///   inspect(clock.pump(samples=4210), content="0")
///   inspect(clock.pump(samples=1), content="1")
/// }
/// ```
pub(all) struct TickClock {
  priv num : Int
  priv den : Int
  priv mut acc : Int
}

///|
/// Builds a clock with `num = sample_rate * 60` and
/// `den = dotted_quarter_bpm * 3`, so one tick is `num / den` samples.
/// Aborts unless both arguments are positive.
pub fn TickClock::new(
  sample_rate~ : Int,
  dotted_quarter_bpm~ : Int,
) -> TickClock {
  if sample_rate <= 0 || dotted_quarter_bpm <= 0 {
    abort(
      "TickClock::new: require sample_rate > 0 and dotted_quarter_bpm > 0, got sample_rate=\{sample_rate} dotted_quarter_bpm=\{dotted_quarter_bpm}",
    )
  }
  { num: sample_rate * 60, den: dotted_quarter_bpm * 3, acc: 0, }
}

///|
/// Feeds `samples` rendered audio samples into the clock and returns how many
/// eighth-note ticks elapsed. `samples <= 0` is a no-op returning 0.
///
/// Overflow bound: the accumulator stays below `num` between calls, so a call
/// is exact while `samples * den + acc < 2^31` — at the 16000 Hz / 76 BPM
/// anchor that allows pumping ~9 million samples per call. Split larger
/// buffers into smaller `pump` calls; the carried remainder keeps the result
/// exact across calls.
pub fn TickClock::pump(self : TickClock, samples~ : Int) -> Int {
  if samples <= 0 {
    return 0
  }
  let acc = self.acc + samples * self.den
  self.acc = acc % self.num
  acc / self.num
}

///|
/// Converts a tick count into a lower-bound sample count,
/// `floor(ticks * num / den)`. `ticks <= 0` yields 0.
///
/// Computed overflow-safely by splitting `ticks` into quotient and remainder
/// against `den`. Exact for `0 <= ticks <= 2000` at the v0.1 anchor
/// (16000 Hz, 76 BPM); in general the intermediates stay below 2^31 while
/// `sample_rate * dotted_quarter_bpm <= ~11.9 million`.
pub fn TickClock::ticks_to_samples(self : TickClock, ticks~ : Int) -> Int {
  if ticks <= 0 {
    return 0
  }
  let whole = ticks / self.den
  let rest = ticks % self.den
  whole * self.num + rest * self.num / self.den
}
