///|
test "panic TickClock::new rejects a zero sample rate" {
  ignore(@music.TickClock::new(sample_rate=0, dotted_quarter_bpm=76))
}

///|
test "panic TickClock::new rejects a negative tempo" {
  ignore(@music.TickClock::new(sample_rate=16000, dotted_quarter_bpm=-5))
}

///|
test "first tick lands after exactly 4211 samples at 16000 Hz / 76 BPM" {
  let clock = @music.TickClock::new(sample_rate=16000, dotted_quarter_bpm=76)
  inspect(clock.pump(samples=4210), content="0")
  inspect(clock.pump(samples=1), content="1")
}

///|
test "carried remainder makes a later pump(8421) exactly two ticks" {
  let clock = @music.TickClock::new(sample_rate=16000, dotted_quarter_bpm=76)
  inspect(clock.pump(samples=4210), content="0")
  inspect(clock.pump(samples=1), content="1")
  // 108 samples remain carried, so 8421 more complete exactly two ticks.
  inspect(clock.pump(samples=8421), content="2")
  // A fresh clock carries nothing, so the same pump yields one tick.
  let fresh = @music.TickClock::new(sample_rate=16000, dotted_quarter_bpm=76)
  inspect(fresh.pump(samples=8421), content="1")
}

///|
test "pump ignores non-positive sample counts" {
  let clock = @music.TickClock::new(sample_rate=16000, dotted_quarter_bpm=76)
  inspect(clock.pump(samples=0), content="0")
  inspect(clock.pump(samples=-5), content="0")
  // The no-ops left the accumulator untouched: the first tick still lands
  // after exactly 4211 real samples.
  inspect(clock.pump(samples=4211), content="1")
}

///|
test "fractional carry ordering across small pumps" {
  // One eighth is 4210.53 samples at this tempo; two 2105-sample pumps total
  // 4210 samples, so the first tick completes on the very next sample.
  let clock = @music.TickClock::new(sample_rate=16000, dotted_quarter_bpm=76)
  inspect(clock.pump(samples=2105), content="0")
  inspect(clock.pump(samples=2105), content="0")
  inspect(clock.pump(samples=1), content="1")
  // Two pumps of the rounded half-eighth (2106) cross the boundary on the
  // second pump: 0 then 1.
  let halves = @music.TickClock::new(sample_rate=16000, dotted_quarter_bpm=76)
  inspect(halves.pump(samples=2106), content="0")
  inspect(halves.pump(samples=2106), content="1")
}

///|
test "ticks_to_samples floors without overflow" {
  let clock = @music.TickClock::new(sample_rate=16000, dotted_quarter_bpm=76)
  inspect(clock.ticks_to_samples(ticks=-7), content="0")
  inspect(clock.ticks_to_samples(ticks=0), content="0")
  inspect(clock.ticks_to_samples(ticks=1), content="4210")
  inspect(clock.ticks_to_samples(ticks=2), content="8421")
  inspect(clock.ticks_to_samples(ticks=3), content="12631")
  inspect(clock.ticks_to_samples(ticks=2000), content="8421052")
}

///|
test "independent clocks keep separate accumulators" {
  let a = @music.TickClock::new(sample_rate=16000, dotted_quarter_bpm=76)
  let b = @music.TickClock::new(sample_rate=16000, dotted_quarter_bpm=76)
  let feed = [4210, 1, 8421, 0, -5, 2105, 2105, 1]
  let results_a : Array[Int] = []
  let results_b : Array[Int] = []
  for samples in feed {
    results_a.push(a.pump(samples~))
    results_b.push(b.pump(samples~))
  }
  debug_inspect(results_a, content="[0, 1, 2, 0, 0, 0, 0, 1]")
  debug_inspect(results_b, content="[0, 1, 2, 0, 0, 0, 0, 1]")
}
