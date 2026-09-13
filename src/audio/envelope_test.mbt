// Envelope, release and mixing behavior — all assertions derived from the
// documented per-waveform presets (see `envelope_preset` in voice.mbt).

///|
fn slice_max(buf : FixedArray[Int]) -> Int {
  let mut best = buf[0]
  for i in 1..<buf.length() {
    if buf[i] > best {
      best = buf[i]
    }
  }
  best
}

///|
test "envelope decays across slices and returns to silence after the gate" {
  // Pulse12 (celesta): attack 4 samples, decay 16/sample to 6%, gate 2400
  // then release 32/sample — audible silence by ~sample 3250.
  let synth = @audio.Synth::new()
  synth.trigger(voice=0, on=note(69, @music.Pulse12), gate_samples=2400)
  let s1 : FixedArray[Int] = FixedArray::make(512, 0)
  synth.render(out=s1) // samples 0..512
  let s2 : FixedArray[Int] = FixedArray::make(512, 0)
  synth.render(out=s2) // samples 512..1024
  let s3 : FixedArray[Int] = FixedArray::make(512, 0)
  synth.render(out=s3) // samples 1024..1536
  let peak1 = slice_max(s1)
  let peak2 = slice_max(s2)
  let peak3 = slice_max(s3)
  // The decay stage must make each later slice strictly quieter.
  inspect(peak1 > peak2 && peak2 > peak3, content="true")
  // Pulse12's 4-sample attack reaches full scale inside the first slice.
  inspect(peak1, content="12000")
  // The third slice tops out on the decaying envelope (~74% of peak1).
  inspect(peak3, content="8917")
  // Render well past gate exhaustion + release: the voice is silent again.
  let drain : FixedArray[Int] = FixedArray::make(3072, 0)
  synth.render(out=drain) // samples 1536..4608
  let after : FixedArray[Int] = FixedArray::make(256, 1)
  synth.render(out=after)
  inspect(count_nonzero(after), content="0")
}

///|
test "an early release shortens the audible duration" {
  let short = @audio.Synth::new()
  let long = @audio.Synth::new()
  short.trigger(voice=0, on=note(60, @music.Pulse50), gate_samples=8000)
  long.trigger(voice=0, on=note(60, @music.Pulse50), gate_samples=8000)
  let chunk : FixedArray[Int] = FixedArray::make(500, 0)
  for _ in 0..<4 {
    short.render(out=chunk)
    long.render(out=chunk)
  }
  // After 2000 shared samples, `short` is released while `long` keeps its
  // full gate and only then enters its slow release.
  short.release(voice=0)
  let mut short_audible = 0
  let mut long_audible = 0
  for _ in 0..<80 {
    short.render(out=chunk)
    short_audible += count_nonzero(chunk)
    long.render(out=chunk)
    long_audible += count_nonzero(chunk)
  }
  inspect(short_audible > 0, content="true")
  inspect(short_audible < long_audible, content="true")
  // Both voices end up fully silent within the rendering window.
  short.render(out=chunk)
  inspect(count_nonzero(chunk), content="0")
  long.render(out=chunk)
  inspect(count_nonzero(chunk), content="0")
}

///|
test "an idle voice is a no-op for release" {
  let synth = @audio.Synth::new()
  synth.release(voice=2)
  // The synth stays idle and keeps rendering silence.
  let out : FixedArray[Int] = FixedArray::make(64, 3)
  synth.render(out~)
  inspect(count_nonzero(out), content="0")
}

///|
test "two simultaneous voices mix as the exact sum of their solo renders" {
  let mixed = @audio.Synth::new()
  mixed.trigger(voice=0, on=note(60, @music.Pulse50), gate_samples=4000)
  mixed.trigger(voice=1, on=note(64, @music.Triangle), gate_samples=4000)
  let solo_a = @audio.Synth::new()
  solo_a.trigger(voice=0, on=note(60, @music.Pulse50), gate_samples=4000)
  let solo_b = @audio.Synth::new()
  solo_b.trigger(voice=0, on=note(64, @music.Triangle), gate_samples=4000)
  let buf_m : FixedArray[Int] = FixedArray::make(1024, 0)
  let buf_a : FixedArray[Int] = FixedArray::make(1024, 0)
  let buf_b : FixedArray[Int] = FixedArray::make(1024, 0)
  mixed.render(out=buf_m)
  solo_a.render(out=buf_a)
  solo_b.render(out=buf_b)
  // Peak 12000 per voice: 24000 < 32767, so the mix is the exact sum with
  // no clamping.
  let mut exact = true
  for i in 0..<1024 {
    if buf_m[i] != buf_a[i] + buf_b[i] {
      exact = false
    }
  }
  inspect(exact, content="true")
  // First mixed sample: Pulse50 attack (+11) plus Triangle attack (-47).
  inspect(buf_m[0], content="-36")
}

///|
test "four loud noise voices clamp into PCM16 without panicking" {
  let synth = @audio.Synth::new()
  for v in 0..<4 {
    synth.trigger(voice=v, on=note(48 + v * 7, @music.Noise), gate_samples=512)
  }
  let out : FixedArray[Int] = FixedArray::make(256, 0)
  synth.render(out~)
  // All four LFSR streams start from the same seed, so the voices share
  // polarity every sample: 4 x 12000 = 48000 clamps hard on both rails.
  let mut lo = out[0]
  let mut hi = out[0]
  for i in 1..<256 {
    if out[i] < lo {
      lo = out[i]
    }
    if out[i] > hi {
      hi = out[i]
    }
  }
  inspect(hi, content="32767")
  inspect(lo, content="-32768")
}
