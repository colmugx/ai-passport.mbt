///|
test "panic TickClock::new rejects a zero sample rate" {
  ignore(
    @music.TickClock::new(
      sample_rate=0,
      dotted_quarter_bpm=76,
      ticks_per_eighth=4,
    ),
  )
}

///|
test "panic TickClock::new rejects a negative tempo" {
  ignore(
    @music.TickClock::new(
      sample_rate=16000,
      dotted_quarter_bpm=-5,
      ticks_per_eighth=4,
    ),
  )
}

///|
test "panic TickClock::new rejects a zero tick resolution" {
  ignore(
    @music.TickClock::new(
      sample_rate=16000,
      dotted_quarter_bpm=76,
      ticks_per_eighth=0,
    ),
  )
}

///|
test "panic TickClock::new rejects a tick shorter than one sample" {
  // den = 100000 * 3 * 100 = 30000000 exceeds num = 960000: a tick below one
  // sample has no sample-accurate meaning for the segment-based transport.
  ignore(
    @music.TickClock::new(
      sample_rate=16000,
      dotted_quarter_bpm=100000,
      ticks_per_eighth=100,
    ),
  )
}

///|
test "first tick lands after exactly 1053 samples at 16000 Hz / 76 BPM / 4 tpe" {
  // One song tick = 16000*60 / (76*3*4) = 1052.63 samples.
  let clock = @music.TickClock::new(
    sample_rate=16000,
    dotted_quarter_bpm=76,
    ticks_per_eighth=4,
  )
  inspect(clock.pump(samples=1052), content="0")
  inspect(clock.pump(samples=1), content="1")
}

///|
test "resolution 1 reproduces the eighth-note anchor of 4211 samples" {
  let clock = @music.TickClock::new(
    sample_rate=16000,
    dotted_quarter_bpm=76,
    ticks_per_eighth=1,
  )
  inspect(clock.pump(samples=4210), content="0")
  inspect(clock.pump(samples=1), content="1")
}

///|
test "carried remainder makes a later pump(2105) exactly two ticks" {
  let clock = @music.TickClock::new(
    sample_rate=16000,
    dotted_quarter_bpm=76,
    ticks_per_eighth=4,
  )
  inspect(clock.pump(samples=1052), content="0")
  inspect(clock.pump(samples=1), content="1")
  // 336 ticks worth of samples remain carried, so 2105 more complete
  // exactly two song ticks.
  inspect(clock.pump(samples=2105), content="2")
  // A fresh clock carries nothing, so the same pump yields one tick.
  let fresh = @music.TickClock::new(
    sample_rate=16000,
    dotted_quarter_bpm=76,
    ticks_per_eighth=4,
  )
  inspect(fresh.pump(samples=2105), content="1")
}

///|
test "pump ignores non-positive sample counts" {
  let clock = @music.TickClock::new(
    sample_rate=16000,
    dotted_quarter_bpm=76,
    ticks_per_eighth=4,
  )
  inspect(clock.pump(samples=0), content="0")
  inspect(clock.pump(samples=-5), content="0")
  // The no-ops left the accumulator untouched: the first tick still lands
  // after exactly 1053 real samples.
  inspect(clock.pump(samples=1053), content="1")
}

///|
test "fractional carry ordering across small pumps" {
  // One song tick is 1052.63 samples at this tempo; two 526-sample pumps
  // total 1052 samples, so the first tick completes on the very next sample.
  let clock = @music.TickClock::new(
    sample_rate=16000,
    dotted_quarter_bpm=76,
    ticks_per_eighth=4,
  )
  inspect(clock.pump(samples=526), content="0")
  inspect(clock.pump(samples=526), content="0")
  inspect(clock.pump(samples=1), content="1")
  // Two pumps of the rounded half-tick (527) cross the boundary on the
  // second pump: 0 then 1.
  let halves = @music.TickClock::new(
    sample_rate=16000,
    dotted_quarter_bpm=76,
    ticks_per_eighth=4,
  )
  inspect(halves.pump(samples=527), content="0")
  inspect(halves.pump(samples=527), content="1")
}

///|
test "ticks_to_samples floors without overflow" {
  let clock = @music.TickClock::new(
    sample_rate=16000,
    dotted_quarter_bpm=76,
    ticks_per_eighth=4,
  )
  inspect(clock.ticks_to_samples(ticks=-7), content="0")
  inspect(clock.ticks_to_samples(ticks=0), content="0")
  inspect(clock.ticks_to_samples(ticks=1), content="1052")
  inspect(clock.ticks_to_samples(ticks=2), content="2105")
  inspect(clock.ticks_to_samples(ticks=3), content="3157")
  // One dotted quarter = 12 song ticks = the historical 12631-sample beat.
  inspect(clock.ticks_to_samples(ticks=12), content="12631")
  inspect(clock.ticks_to_samples(ticks=8000), content="8421052")
}

///|
test "ticks_to_samples_exact measures from the current phase to the boundary" {
  let clock = @music.TickClock::new(
    sample_rate=16000,
    dotted_quarter_bpm=76,
    ticks_per_eighth=4,
  )
  inspect(clock.ticks_to_samples_exact(ticks=0), content="0")
  inspect(clock.ticks_to_samples_exact(ticks=-3), content="0")
  // From phase 0 the exact distance is ceil(k * 1052.63...) per k — one
  // above the floor of ticks_to_samples whenever the fraction is nonzero.
  inspect(clock.ticks_to_samples_exact(ticks=1), content="1053")
  inspect(clock.ticks_to_samples_exact(ticks=2), content="2106")
  inspect(clock.ticks_to_samples_exact(ticks=3), content="3158")
  // One dotted quarter from phase 0: 12632, not the nominal 12631.
  inspect(clock.ticks_to_samples_exact(ticks=12), content="12632")
  // Long spans stay overflow-safe through the quotient/remainder split.
  inspect(clock.ticks_to_samples_exact(ticks=8000), content="8421053")
  // After the first boundary the accumulator carries 336: the distance to
  // the next boundary is still 1053 and four ticks still land on the anchor
  // boundary at 1053 + 4211 = 5264.
  let _ = clock.pump(samples=1053)
  inspect(clock.ticks_to_samples_exact(ticks=1), content="1053")
  inspect(clock.ticks_to_samples_exact(ticks=4), content="4211")
}

///|
test "ticks_to_samples_exact equals the sum of the next greedy segments" {
  // Brute-force the segment definition — repeatedly hop to the next tick
  // boundary — and require the closed form to agree, for a spread of spans
  // including sub-tick and multi-tick sizes.
  for n in [1, 2, 3, 5, 12, 13, 47, 100, 912] {
    let clock = @music.TickClock::new(
      sample_rate=16000,
      dotted_quarter_bpm=76,
      ticks_per_eighth=4,
    )
    let exact = clock.ticks_to_samples_exact(ticks=n)
    let brute = @music.TickClock::new(
      sample_rate=16000,
      dotted_quarter_bpm=76,
      ticks_per_eighth=4,
    )
    let mut total = 0
    for _ in 0..<n {
      let seg = brute.samples_to_next_tick()
      total += seg
      let _ = brute.pump(samples=seg)
    }
    assert_eq(exact, total)
  }
}

///|
test "independent clocks keep separate accumulators" {
  let a = @music.TickClock::new(
    sample_rate=16000,
    dotted_quarter_bpm=76,
    ticks_per_eighth=4,
  )
  let b = @music.TickClock::new(
    sample_rate=16000,
    dotted_quarter_bpm=76,
    ticks_per_eighth=4,
  )
  let feed = [1052, 1, 2105, 0, -5, 526, 526, 1]
  let results_a : Array[Int] = []
  let results_b : Array[Int] = []
  for samples in feed {
    results_a.push(a.pump(samples~))
    results_b.push(b.pump(samples~))
  }
  debug_inspect(results_a, content="[0, 1, 2, 0, 0, 0, 0, 1]")
  debug_inspect(results_b, content="[0, 1, 2, 0, 0, 0, 0, 1]")
}
