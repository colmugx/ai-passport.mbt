///|
/// Deterministic integer bridge from audio samples to song ticks.
///
/// One song tick lasts `60 / (dotted_quarter_bpm * 3 * ticks_per_eighth)`
/// seconds — an eighth note divided by the song's resolution — which is
/// `sample_rate * 60 / (dotted_quarter_bpm * 3 * ticks_per_eighth)` samples;
/// the fractional remainder is carried exactly, Bresenham-style. No floats
/// anywhere.
///
/// # Example
/// ```mbt check
/// test {
///   let clock = TickClock::new(
///     sample_rate=16000,
///     dotted_quarter_bpm=76,
///     ticks_per_eighth=4,
///   )
///   inspect(clock.pump(samples=1052), content="0")
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
/// `den = dotted_quarter_bpm * 3 * ticks_per_eighth`, so one song tick is
/// `num / den` samples. Aborts unless every argument is positive.
pub fn TickClock::new(
  sample_rate~ : Int,
  dotted_quarter_bpm~ : Int,
  ticks_per_eighth~ : Int,
) -> TickClock {
  if sample_rate <= 0 || dotted_quarter_bpm <= 0 || ticks_per_eighth <= 0 {
    abort(
      "TickClock::new: require sample_rate > 0, dotted_quarter_bpm > 0 and ticks_per_eighth > 0, got sample_rate=\{sample_rate} dotted_quarter_bpm=\{dotted_quarter_bpm} ticks_per_eighth=\{ticks_per_eighth}",
    )
  }
  {
    num: sample_rate * 60,
    den: dotted_quarter_bpm * 3 * ticks_per_eighth,
    acc: 0,
  }
}

///|
/// Feeds `samples` rendered audio samples into the clock and returns how many
/// song ticks elapsed. `samples <= 0` is a no-op returning 0.
///
/// Overflow bound: the accumulator stays below `num` between calls, so a call
/// is exact while `samples * den + acc < 2^31` — at the 16000 Hz / 76 BPM /
/// 4 ticks-per-eighth anchor that allows pumping ~2.3 million samples per
/// call. Split larger buffers into smaller `pump` calls; the carried
/// remainder keeps the result exact across calls.
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
/// against `den`. Exact for `0 <= ticks <= 8000` at the v0.1 anchor
/// (16000 Hz, 76 BPM, 4 ticks per eighth); in general the intermediates stay
/// below 2^31 while `sample_rate * dotted_quarter_bpm <= ~11.9 million`.
pub fn TickClock::ticks_to_samples(self : TickClock, ticks~ : Int) -> Int {
  if ticks <= 0 {
    return 0
  }
  let whole = ticks / self.den
  let rest = ticks % self.den
  whole * self.num + rest * self.num / self.den
}

///|
/// Samples remaining until the next tick boundary, from `1` to one full
/// tick period. A caller that renders exactly this many samples lands
/// exactly on the boundary where the next tick fires — the primitive the
/// audio `Player` uses for sample-accurate event scheduling inside output
/// buffers.
pub fn TickClock::samples_to_next_tick(self : TickClock) -> Int {
  (self.num - self.acc + self.den - 1) / self.den
}
