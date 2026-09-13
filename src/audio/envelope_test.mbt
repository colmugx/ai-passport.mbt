// Envelope, release and mixing behavior — all assertions derived from the
// documented instrument presets (see `Instrument::celesta()` and friends in
// @music, converted to per-sample steps by `build_preset` in voice.mbt).

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
  // Celesta (Pulse12): instant attack, decay 16/sample to 6%, gate 2400
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
  // The instant attack reaches full scale inside the first slice.
  inspect(peak1, content="12000")
  // The third slice tops out on the decaying envelope (~74% of peak1).
  inspect(peak3, content="8909")
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

///|
/// Builds a NoteOn with a bespoke instrument for envelope-clamp tests.
fn clamp_note(instrument : @music.Instrument) -> @music.NoteOn {
  {
    track: 0,
    pitch: @music.Pitch::from_midi(midi=69).unwrap(),
    ticks: 100,
    instrument,
  }
}

///|
test "a positive attack longer than the envelope scale clamps to a 1-unit step" {
  // 4224 ms = 67584 samples exceeds the 65536-unit envelope scale, so
  // 65536 / 67584 floors to 0 — the clamp makes it a 1-unit step and the
  // attack completes in 65536 samples instead of stalling forever.
  let instrument : @music.Instrument = {
    name: "Slow Attack",
    waveform: @music.Pulse50,
    envelope: {
      attack_ms: 4224,
      decay_ms: 0,
      sustain: 65536,
      release_ms: 4224,
    },
    volume: 100,
    vibrato: None,
  }
  let synth = @audio.Synth::new()
  synth.trigger(voice=0, on=clamp_note(instrument), gate_samples=70000)
  let out : FixedArray[Int] = FixedArray::make(139264, 0)
  synth.render(out~)
  // The ramp is exactly one envelope unit per sample: env 1 at sample 0
  // (below audible resolution), env 32769 at sample 32768, full scale at
  // sample 65535 — the attack completed instead of stalling.
  inspect(out[0], content="0")
  inspect(out[32768], content="6000")
  inspect(out[65535], content="12000")
  // The 70000-sample gate exhausts and release runs at one unit per sample:
  // env 65534 at sample 70001 — a stalled 0-step would still read full
  // scale there.
  inspect(out[70001], content="11999")
  // The fade completes after 65536 release samples and the voice
  // deactivates instead of leaking a frozen level.
  inspect(out[135535], content="0")
  inspect(out[135536], content="0")
  inspect(out[139263], content="0")
}

///|
test "a positive decay longer than the envelope scale clamps to a 1-unit step" {
  // 8224 ms = 131584 samples: (65536 - 0) / 131584 floors to 0 — clamped to
  // 1, so the decay reaches the sustain floor after 65536 samples.
  let instrument : @music.Instrument = {
    name: "Slow Decay",
    waveform: @music.Pulse50,
    envelope: { attack_ms: 0, decay_ms: 8224, sustain: 0, release_ms: 0, },
    volume: 100,
    vibrato: None,
  }
  let synth = @audio.Synth::new()
  synth.trigger(voice=0, on=clamp_note(instrument), gate_samples=200000)
  let out : FixedArray[Int] = FixedArray::make(66000, 0)
  synth.render(out~)
  // Instant attack at full scale, then exactly one unit down per sample:
  // env 32768 at sample 32768, env 25536 at sample 40000 (its floor on the
  // negative half-wave is -4676 — a stalled 0-step would read full scale).
  inspect(out[0], content="12000")
  inspect(out[32768], content="6000")
  inspect(out[40000], content="-4676")
  // The ramp hits the sustain floor (silence) at sample 65536.
  inspect(out[65536], content="0")
  inspect(out[65999], content="0")
}

///|
test "a positive release longer than the envelope scale clamps to a 1-unit step" {
  // 8224 ms = 131584 samples: 65536 / 131584 floors to 0 — clamped to 1, so
  // the release fades out over 65536 samples instead of hanging forever.
  let instrument : @music.Instrument = {
    name: "Slow Release",
    waveform: @music.Pulse50,
    envelope: { attack_ms: 0, decay_ms: 0, sustain: 65536, release_ms: 8224, },
    volume: 100,
    vibrato: None,
  }
  let synth = @audio.Synth::new()
  synth.trigger(voice=0, on=clamp_note(instrument), gate_samples=1000)
  let out : FixedArray[Int] = FixedArray::make(67000, 0)
  synth.render(out~)
  // Full scale through the whole gate; release begins exactly at gate end
  // (env 65535 at sample 1000, env 33536 at sample 33000).
  inspect(out[999], content="12000")
  inspect(out[1000], content="11999")
  inspect(out[33000], content="6140")
  // The fade completes and the voice goes idle instead of leaking a
  // frozen nonzero level.
  inspect(out[66535], content="0")
  inspect(out[66536], content="0")
  inspect(out[66999], content="0")
}
