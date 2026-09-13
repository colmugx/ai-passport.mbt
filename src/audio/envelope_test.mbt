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
test "a 100 ms attack reaches full scale exactly at 1600 samples" {
  // 100 ms = 1600 samples; 65536 / 1600 = 40 remainder 1536, so the
  // Bresenham ramp adds 40 units every sample plus one extra unit 1536
  // times, landing on the full scale at exactly sample 1600.
  let instrument : @music.Instrument = {
    name: "Ramp Attack",
    waveform: @music.Pulse50,
    envelope: { attack_ms: 100, decay_ms: 0, sustain: 65536, release_ms: 8224, },
    volume: 100,
    vibrato: None,
  }
  let synth = @audio.Synth::new()
  synth.trigger(voice=0, on=clamp_note(instrument), gate_samples=4000)
  let out : FixedArray[Int] = FixedArray::make(4000, 0)
  synth.render(out~)
  inspect(out[0], content="7")
  inspect(out[1598], content="-11993")
  inspect(out[1599], content="-12000")
  // After reaching the target the attack does not overshoot: the level is
  // held (decay is instant to the full-scale sustain).
  inspect(out[3000], content="12000")
}

///|
test "an 8-second attack lasts 8 seconds, not the old 4.096 s clamp" {
  // 8000 ms = 128000 samples with a 65536-unit span: the whole step floors
  // to 0, so the ramp advances purely through the carried remainder and
  // must still reach full scale exactly at sample 128000 (the previous
  // max(1) clamp finished around 4.096 s; a zero step would stall forever).
  let instrument : @music.Instrument = {
    name: "Eight Second Attack",
    waveform: @music.Pulse50,
    envelope: {
      attack_ms: 8000,
      decay_ms: 0,
      sustain: 65536,
      release_ms: 8224,
    },
    volume: 100,
    vibrato: None,
  }
  let synth = @audio.Synth::new()
  synth.trigger(voice=0, on=clamp_note(instrument), gate_samples=200000)
  let out : FixedArray[Int] = FixedArray::make(139264, 0)
  synth.render(out~)
  // Halfway through, the level is only about half scale — the old max(1)
  // clamp would already read full scale here.
  inspect(out[65535], content="6143")
  inspect(out[65536], content="6143")
  // The ramp's final units land within the last two samples (their floors
  // read as full scale on the negative half-wave) and the level is held
  // afterwards: no stall, no 4.096 s shortcut.
  inspect(out[127998], content="-12000")
  inspect(out[127999], content="-12000")
  inspect(out[135000], content="12000")
}

///|
test "a small-span decay still lasts the requested ms" {
  // Sustain sits 40 units below full scale and decay_ms 100 = 1600 samples:
  // span 40 < 1600, so the whole step floors to 0. The carried remainder
  // removes one unit every 40 samples — the decay lands on the sustain
  // level exactly at sample 1600 instead of jumping there in 40 samples.
  let instrument : @music.Instrument = {
    name: "Small Span Decay",
    waveform: @music.Pulse50,
    envelope: { attack_ms: 0, decay_ms: 100, sustain: 65496, release_ms: 0, },
    volume: 100,
    vibrato: None,
  }
  let synth = @audio.Synth::new()
  synth.trigger(voice=0, on=clamp_note(instrument), gate_samples=4000)
  let out : FixedArray[Int] = FixedArray::make(4000, 0)
  synth.render(out~)
  // One unit is removed exactly every 40 samples (1600 / 40): the level is
  // still full at sample 39, takes its first unit at 40, is 20 units down
  // at the halfway mark, and lands on the sustain level at sample 1600,
  // holding it afterwards — the old max(1) clamp would have finished the
  // whole 40-unit decay within 40 samples.
  inspect(out[39], content="12000")
  inspect(out[40], content="11999")
  inspect(out[800], content="-11997")
  inspect(out[1599], content="-11993")
  inspect(out[1600], content="-11993")
  inspect(out[3000], content="11992")
}

///|
test "a long release reaches zero at the requested duration" {
  // 8000 ms = 128000 samples of release from full scale: the level halves
  // exactly at half the duration and hits zero at the full duration, where
  // the voice deactivates — no stall, no 4.096 s shortcut.
  let instrument : @music.Instrument = {
    name: "Eight Second Release",
    waveform: @music.Pulse50,
    envelope: { attack_ms: 0, decay_ms: 0, sustain: 65536, release_ms: 8000, },
    volume: 100,
    vibrato: None,
  }
  let synth = @audio.Synth::new()
  synth.trigger(voice=0, on=clamp_note(instrument), gate_samples=16)
  let out : FixedArray[Int] = FixedArray::make(129000, 0)
  synth.render(out~)
  // Release begins at gate end: sample 15 still reads full scale and the
  // first release advance happens at sample 16 (its first unit lands two
  // samples in, since 65536 x 2 crosses the 128000-sample modulus).
  inspect(out[15], content="12000")
  inspect(out[16], content="12000")
  // Exact halfway and quarter points: env 32768 and 49152.
  inspect(out[64016], content="6000")
  inspect(out[32016], content="9000")
  // The tail keeps descending to silence at sample 16 + 128000, where the
  // voice deactivates.
  inspect(out[70000], content="-5439")
  inspect(out[128015], content="0")
  inspect(out[128016], content="0")
  inspect(out[128999], content="0")
}

///|
test "an 8-second decay completes instead of stalling" {
  // The decay must reach the sustain floor exactly at the requested
  // duration — a stalled stage would hold full scale forever.
  let instrument : @music.Instrument = {
    name: "Eight Second Decay",
    waveform: @music.Pulse50,
    envelope: { attack_ms: 0, decay_ms: 8000, sustain: 0, release_ms: 0, },
    volume: 100,
    vibrato: None,
  }
  let synth = @audio.Synth::new()
  synth.trigger(voice=0, on=clamp_note(instrument), gate_samples=200000)
  let out : FixedArray[Int] = FixedArray::make(139264, 0)
  synth.render(out~)
  inspect(out[65535], content="5856")
  inspect(out[128000], content="0")
  inspect(out[139263], content="0")
}

///|
/// Checks the complete PCM release curve against the configured duration.
/// A full-level reference voice supplies the oscillator polarity, while
/// `start_env - floor(start_env * elapsed / duration)` defines the expected
/// envelope independently of the incremental renderer.
fn check_release_curve(
  label : String,
  attack_ms : Int,
  decay_ms : Int,
  sustain : Int,
  release_ms : Int,
  warmup : Int,
  start_env : Int,
) -> Unit raise {
  let instrument : @music.Instrument = {
    name: label,
    waveform: @music.Pulse50,
    envelope: { attack_ms, decay_ms, sustain, release_ms, },
    volume: 100,
    vibrato: None,
  }
  let reference_instrument : @music.Instrument = {
    name: "Full Level Reference",
    waveform: @music.Pulse50,
    envelope: { attack_ms: 0, decay_ms: 0, sustain: 65536, release_ms: 0, },
    volume: 100,
    vibrato: None,
  }
  let duration = release_ms * 16
  let explicit = @audio.Synth::new()
  let automatic = @audio.Synth::new()
  let reference = @audio.Synth::new()
  explicit.trigger(
    voice=0,
    on=clamp_note(instrument),
    gate_samples=warmup + duration + 8,
  )
  automatic.trigger(voice=0, on=clamp_note(instrument), gate_samples=warmup)
  reference.trigger(
    voice=0,
    on=clamp_note(reference_instrument),
    gate_samples=warmup + duration + 8,
  )
  let before : FixedArray[Int] = FixedArray::make(warmup, 0)
  explicit.render(out=before)
  automatic.render(out=before)
  reference.render(out=before)
  explicit.release(voice=0)
  let observed : FixedArray[Int] = FixedArray::make(duration + 1, 0)
  let gated : FixedArray[Int] = FixedArray::make(duration + 1, 0)
  let full : FixedArray[Int] = FixedArray::make(duration + 1, 0)
  explicit.render(out=observed)
  automatic.render(out=gated)
  reference.render(out=full)
  let mut exact = true
  let mut matching_entry_paths = true
  for i in 0..<duration {
    let removed = (Int64::from_int(start_env) *
    Int64::from_int(i + 1) /
    Int64::from_int(duration)).to_int()
    let expected = (full[i] * (start_env - removed)) >> 16
    if observed[i] != expected {
      exact = false
    }
    if observed[i] != gated[i] {
      matching_entry_paths = false
    }
  }
  inspect(exact, content="true")
  inspect(matching_entry_paths, content="true")
  inspect(observed[duration], content="0")
  inspect(gated[duration], content="0")
}

///|
test "partial sustain releases for exactly the configured sample count" {
  check_release_curve("Low Sustain", 0, 0, 4096, 128, 16, 4096)
  check_release_curve("Half Sustain", 0, 0, 32768, 100, 16, 32768)
}

///|
test "attack and decay release from their current levels for full duration" {
  // 400 of 1600 attack samples: level 16384.
  check_release_curve("Attack Entry", 100, 0, 32768, 128, 400, 16384)
  // One instant-attack sample plus 400 of 1600 decay samples: level 57344.
  check_release_curve("Decay Entry", 0, 100, 32768, 100, 401, 57344)
}

///|
test "a long release from low sustain keeps its remainder moving" {
  check_release_curve("Long Partial Release", 0, 0, 4096, 8000, 16, 4096)
}

///|
test "zero millisecond release silences the next release sample" {
  let instrument : @music.Instrument = {
    name: "Instant Release",
    waveform: @music.Pulse50,
    envelope: { attack_ms: 0, decay_ms: 0, sustain: 32768, release_ms: 0, },
    volume: 100,
    vibrato: None,
  }
  let explicit = @audio.Synth::new()
  explicit.trigger(voice=0, on=clamp_note(instrument), gate_samples=64)
  let before : FixedArray[Int] = FixedArray::make(16, 0)
  explicit.render(out=before)
  explicit.release(voice=0)
  let after : FixedArray[Int] = FixedArray::make(16, 7)
  explicit.render(out=after)
  inspect(count_nonzero(after), content="0")

  let automatic = @audio.Synth::new()
  automatic.trigger(voice=0, on=clamp_note(instrument), gate_samples=16)
  automatic.render(out=before)
  automatic.render(out=after)
  inspect(count_nonzero(after), content="0")
}
