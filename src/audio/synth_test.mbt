// Black-box tests for the pure synth core. Every test is deterministic:
// the DSP has no randomness (the noise LFSR restarts from a fixed seed on
// each trigger), so identical operations produce identical buffers.

///|
/// Builds a note-start event like the ones the `@music.Sequencer` emits.
fn note(midi : Int, waveform : @music.Waveform) -> @music.NoteOn {
  let pitch = @music.Pitch::from_midi(midi~).unwrap()
  { track: 0, pitch, eighths: 2, waveform, }
}

///|
fn count_nonzero(buf : FixedArray[Int]) -> Int {
  let mut count = 0
  for i in 0..<buf.length() {
    if buf[i] != 0 {
      count += 1
    }
  }
  count
}

///|
fn buffers_equal(a : FixedArray[Int], b : FixedArray[Int]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
test "idle render is silence at any chunk length" {
  let synth = @audio.Synth::new()
  let out : FixedArray[Int] = FixedArray::make(256, 1234)
  synth.render(out~)
  inspect(count_nonzero(out), content="0")
  let tiny : FixedArray[Int] = FixedArray::make(1, 1234)
  synth.render(out=tiny)
  inspect(count_nonzero(tiny), content="0")
  // Length 0 is a documented no-op and must not panic.
  let empty : FixedArray[Int] = []
  synth.render(out=empty)
}

///|
test "panic Synth::trigger rejects voice -1" {
  let synth = @audio.Synth::new()
  synth.trigger(voice=-1, on=note(60, @music.Pulse50), gate_samples=256)
}

///|
test "panic Synth::trigger rejects voice 4" {
  let synth = @audio.Synth::new()
  synth.trigger(voice=4, on=note(60, @music.Pulse50), gate_samples=256)
}

///|
test "panic Synth::trigger rejects a zero gate" {
  let synth = @audio.Synth::new()
  synth.trigger(voice=0, on=note(60, @music.Pulse50), gate_samples=0)
}

///|
test "panic Synth::release rejects an out-of-range voice" {
  let synth = @audio.Synth::new()
  synth.release(voice=4)
}

///|
test "a triggered Pulse50 note renders nonzero samples deterministically" {
  let a = @audio.Synth::new()
  let b = @audio.Synth::new()
  a.trigger(voice=0, on=note(60, @music.Pulse50), gate_samples=512)
  b.trigger(voice=0, on=note(60, @music.Pulse50), gate_samples=512)
  let buf_a : FixedArray[Int] = FixedArray::make(256, 0)
  let buf_b : FixedArray[Int] = FixedArray::make(256, 0)
  a.render(out=buf_a)
  b.render(out=buf_b)
  inspect(count_nonzero(buf_a) > 0, content="true")
  // Two identically-driven synths produce identical buffers.
  inspect(buffers_equal(buf_a, buf_b), content="true")
  // Fixed-index snapshot of the strings swell (Pulse50 attack adds 64
  // envelope units per sample, so the ramp is audible sample by sample).
  inspect(buf_a[0], content="11")
  inspect(buf_a[64], content="761")
  inspect(buf_a[255], content="3000")
}

///|
test "noise is deterministic from its fixed LFSR seed" {
  let a = @audio.Synth::new()
  let b = @audio.Synth::new()
  a.trigger(voice=0, on=note(69, @music.Noise), gate_samples=512)
  b.trigger(voice=0, on=note(69, @music.Noise), gate_samples=512)
  let buf_a : FixedArray[Int] = FixedArray::make(256, 0)
  let buf_b : FixedArray[Int] = FixedArray::make(256, 0)
  a.render(out=buf_a)
  b.render(out=buf_b)
  inspect(buffers_equal(buf_a, buf_b), content="true")
  // Retriggering restarts the LFSR, so the same synth replays the same
  // noise buffer for the same trigger+render sequence.
  let replay : FixedArray[Int] = FixedArray::make(256, 0)
  a.trigger(voice=0, on=note(69, @music.Noise), gate_samples=512)
  a.render(out=replay)
  inspect(buffers_equal(buf_a, replay), content="true")
  inspect(count_nonzero(buf_a) > 0, content="true")
}

///|
test "waveforms on the same pitch produce different buffers" {
  let waveforms = [
    @music.Pulse12,
    @music.Pulse25,
    @music.Pulse50,
    @music.Triangle,
    @music.Noise,
  ]
  let bufs : Array[FixedArray[Int]] = []
  for wf in waveforms {
    let synth = @audio.Synth::new()
    synth.trigger(voice=0, on=note(69, wf), gate_samples=512)
    let buf : FixedArray[Int] = FixedArray::make(256, 0)
    synth.render(out=buf)
    bufs.push(buf)
  }
  // Duty cycle: 12.5% vs 25% must differ.
  inspect(buffers_equal(bufs[0], bufs[1]), content="false")
  // Square vs triangle vs noise are different shapes entirely.
  inspect(buffers_equal(bufs[2], bufs[3]), content="false")
  inspect(buffers_equal(bufs[2], bufs[4]), content="false")
  inspect(buffers_equal(bufs[3], bufs[4]), content="false")
}

///|
/// Positions of the polarity flips in a rendered buffer, as deltas in
/// samples between consecutive zero crossings.
fn crossing_deltas(buf : FixedArray[Int]) -> Array[Int] {
  let deltas : Array[Int] = []
  let mut prev_cross = -1
  let mut prev_high = buf[0] > 0
  for i in 1..<buf.length() {
    let high = buf[i] > 0
    if high != prev_high {
      if prev_cross >= 0 {
        deltas.push(i - prev_cross)
      }
      prev_cross = i
      prev_high = high
    }
  }
  deltas
}

///|
fn delta_span(deltas : Array[Int]) -> Int {
  let mut lo = deltas[0]
  let mut hi = deltas[0]
  for d in deltas {
    if d < lo {
      lo = d
    }
    if d > hi {
      hi = d
    }
  }
  hi - lo
}

///|
test "Pulse25 vibrato drifts the zero-crossing period; Pulse50 stays static" {
  // Midi 36 (~65.4 Hz) makes the ~0.78% vibrato swing visible in integer
  // zero-crossing deltas. Crossing deltas are duty segments, so Pulse25
  // alternates a short (~61) and a long (~184) segment per cycle; vibrato
  // sweeps both across several integers, while the static-pitch Pulse50
  // (50% duty, segments ~122.3) only jitters between two adjacent values.
  let wob = @audio.Synth::new()
  wob.trigger(voice=0, on=note(36, @music.Pulse25), gate_samples=16384)
  let buf_wob : FixedArray[Int] = FixedArray::make(8192, 0)
  wob.render(out=buf_wob)
  let still = @audio.Synth::new()
  still.trigger(voice=0, on=note(36, @music.Pulse50), gate_samples=16384)
  let buf_still : FixedArray[Int] = FixedArray::make(8192, 0)
  still.render(out=buf_still)
  let span_wob = delta_span(crossing_deltas(buf_wob))
  let span_still = delta_span(crossing_deltas(buf_still))
  // Static pitch: a fixed period yields exactly two adjacent integer
  // crossing deltas.
  inspect(span_still, content="1")
  // Vibrato sweeps the duty segments across many integers.
  inspect(span_wob, content="125")
  inspect(span_wob >= span_still + 2, content="true")
}

///|
test "the increment table tracks equal temperament (A4 and octave)" {
  // Midi 69 = 440 Hz at 16000 Hz: cycle = 36.38 samples, so Pulse50 duty
  // segments (zero-crossing deltas) must be 18 or 19 samples. Midi 81 = 880
  // Hz halves the cycle: segments 9 or 10. This pins the Float-only
  // increment table against music theory from the public API alone.
  let a4 = @audio.Synth::new()
  a4.trigger(voice=0, on=note(69, @music.Pulse50), gate_samples=4096)
  let buf_a4 : FixedArray[Int] = FixedArray::make(2048, 0)
  a4.render(out=buf_a4)
  let a5 = @audio.Synth::new()
  a5.trigger(voice=0, on=note(81, @music.Pulse50), gate_samples=4096)
  let buf_a5 : FixedArray[Int] = FixedArray::make(2048, 0)
  a5.render(out=buf_a5)
  let d_a4 = crossing_deltas(buf_a4)
  let d_a5 = crossing_deltas(buf_a5)
  inspect(delta_span(d_a4) <= 1, content="true")
  inspect(delta_span(d_a5) <= 1, content="true")
  inspect(d_a4[10], content="18")
  inspect(d_a5[10], content="10")
}
