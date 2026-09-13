// Black-box tests for the Player: sample-accurate scheduling, buffer-size
// independence, pause/resume and beat/loop determinism.

///|
/// Builds a dense four-voice test song: every track plays one-tick notes
/// separated by one-tick rests, so note starts land on many tick boundaries
/// and all four voices sound together.
fn dense_song() -> @music.Song {
  let notes : Array[@music.Note] = []
  for _ in 0..<24 {
    notes.push({ pitch: @music.Pitch::from_midi(midi=69), ticks: 1, })
    notes.push({ pitch: None, ticks: 1, })
  }
  @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[
      { instrument: @music.Instrument::celesta(), notes, },
      { instrument: @music.Instrument::woodwind(), notes, },
      { instrument: @music.Instrument::strings(), notes, },
      { instrument: @music.Instrument::low_strings(), notes, },
    ],
  ) catch {
    err => abort("dense test song violates four-voice cap: \{err}")
  }
}

///|
fn all_zero(buf : FixedArray[Int]) -> Bool {
  for i in 0..<buf.length() {
    if buf[i] != 0 {
      return false
    }
  }
  true
}

///|
test "render(4096) once equals 16 x render(256) sample by sample" {
  // The strong invariant: chunking must not move a single sample, even
  // though 256-sample chunks straddle tick boundaries (one tick is
  // ~1052.63 samples) and note triggers, and the span crosses the loop wrap.
  let whole = Player::new(song=dense_song())
  let reference : FixedArray[Int] = FixedArray::make(4096, 7)
  whole.render(out=reference)

  let chunked = Player::new(song=dense_song())
  let mut all_match = true
  for c in 0..<16 {
    let chunk : FixedArray[Int] = FixedArray::make(256, 7)
    chunked.render(out=chunk)
    for i in 0..<256 {
      if chunk[i] != reference[c * 256 + i] {
        all_match = false
      }
    }
  }
  inspect(all_match, content="true")
}

///|
test "the first note of a song sounds from sample 0" {
  // One 4-tick celesta note at position 0. The transport starts ON tick 0:
  // the note's first sample is output sample 0 (full-scale — the celesta
  // attacks instantly), with no one-tick pre-roll.
  let track : @music.Track = {
    instrument: @music.Instrument::celesta(),
    notes: [{ pitch: @music.Pitch::from_midi(midi=69), ticks: 4, }],
  }
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[track],
  )
  let player = Player::new(song~)
  let first : FixedArray[Int] = FixedArray::make(1, 0)
  player.render(out=first)
  inspect(first[0], content="12000")
  // The transport is still on tick 0 and no beat has elapsed: the tick-0
  // arrival moves nothing.
  inspect(player.position_ticks(), content="0")
  inspect(player.beat(), content="0")
  // The first boundary sits at ceil(960000 / 912) = sample 1053.
  let rest : FixedArray[Int] = FixedArray::make(1052, 0)
  player.render(out=rest)
  inspect(player.position_ticks(), content="1")
  inspect(player.beat(), content="0")
}

///|
test "a note fires exactly at its tick boundary and gates exactly to its end boundary" {
  // A rest of one tick, then a 4-tick celesta note. The note fires on the
  // arrival at tick 1 — the boundary after 1053 samples — and its gate spans
  // the exact phase-aware distance to the boundary 4 ticks later: from the
  // carry (1053 * 912 - 960000 = 336) that is ceil((4*960000 - 336) / 912) =
  // 4211 samples, so release begins exactly at the anchor boundary of tick 5.
  let track : @music.Track = {
    instrument: @music.Instrument::celesta(),
    notes: [
      { pitch: None, ticks: 1, },
      { pitch: @music.Pitch::from_midi(midi=69), ticks: 4, },
    ],
  }
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[track],
  )
  let player = Player::new(song~)
  let a : FixedArray[Int] = FixedArray::make(1053, 0)
  player.render(out=a)
  // The whole first tick is silent: the note fires only on the arrival at
  // tick 1, which happens after this buffer's last sample.
  for i in 0..<1053 {
    assert_eq(a[i], 0)
  }
  inspect(player.position_ticks(), content="1")
  let first : FixedArray[Int] = FixedArray::make(1, 0)
  player.render(out=first)
  inspect(first[0], content="12000")
  // The gate's last sample (note-sample 4210) is still at the sustain level
  // (envelope 4096 of 65536 at peak 12000 -> exactly 750, on the negative
  // half-wave here): release has NOT begun a sample early, which is what the
  // phase-independent floor gate would do.
  let b : FixedArray[Int] = FixedArray::make(4210, 0)
  player.render(out=b)
  inspect(b[4209], content="-750")
  // Release steps 32 envelope units per sample from the sustain level:
  // env 4064 then 4032 on the negative half-wave (floors of -744.14 and
  // -738.28).
  let c : FixedArray[Int] = FixedArray::make(2, 0)
  player.render(out=c)
  inspect(c[0], content="-745")
  inspect(c[1], content="-739")
  // Sample 5264 is the arrival past the loop end: the transport wrapped to
  // tick 0 (the tick-0 rest fires nothing).
  inspect(player.position_ticks(), content="0")
}

///|
test "a loop wrap retriggers the tick-0 note at the exact boundary sample" {
  // One 4-tick note looping forever: the wrap lands on tick 0 at
  // ceil(4 * 960000 / 912) = sample 4211 and re-fires the same note with a
  // fully reset voice, so two consecutive cycles replay sample-exactly.
  // A wrap that fired a single sample early or late would break the halves.
  let track : @music.Track = {
    instrument: @music.Instrument::celesta(),
    notes: [{ pitch: @music.Pitch::from_midi(midi=69), ticks: 4, }],
  }
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[track],
  )
  let whole = Player::new(song~)
  let stream : FixedArray[Int] = FixedArray::make(8422, 0)
  whole.render(out=stream)
  let chunked = Player::new(song~)
  let half_a : FixedArray[Int] = FixedArray::make(4211, 0)
  chunked.render(out=half_a)
  let half_b : FixedArray[Int] = FixedArray::make(4211, 0)
  chunked.render(out=half_b)
  inspect(buffers_equal(half_a, half_b), content="true")
  let tail : FixedArray[Int] = FixedArray::make(4211, 0)
  for i in 0..<4211 {
    tail[i] = stream[4211 + i]
  }
  inspect(buffers_equal(half_a, tail), content="true")
  // Sample 8422 is the second wrap boundary: the transport is back on tick 0.
  inspect(whole.position_ticks(), content="0")
}

///|
test "pause outputs silence and freezes the transport; resume is exact" {
  let a = Player::new(song=dense_song())
  let chunks_a : Array[FixedArray[Int]] = []
  for _ in 0..<5 {
    let chunk : FixedArray[Int] = FixedArray::make(533, 0)
    a.render(out=chunk)
    chunks_a.push(chunk)
  }

  let b = Player::new(song=dense_song())
  for _ in 0..<2 {
    let chunk : FixedArray[Int] = FixedArray::make(533, 0)
    b.render(out=chunk)
  }
  let before = b.position_ticks()
  let beat_before = b.beat()
  b.pause()
  inspect(b.paused(), content="true")
  for _ in 0..<3 {
    let chunk : FixedArray[Int] = FixedArray::make(533, 9)
    b.render(out=chunk)
    // Paused renders are pure silence, whatever the buffer held before.
    inspect(all_zero(chunk), content="true")
  }
  // Pause freezes the elapsed tick AND beat state.
  inspect(b.position_ticks(), content=before.to_string())
  inspect(b.beat(), content=beat_before.to_string())
  b.unpause()
  inspect(b.paused(), content="false")
  // Resumed chunks continue the stream exactly where the pause froze it:
  // they match the never-paused player's chunks 2 and 3 sample by sample.
  let r0 : FixedArray[Int] = FixedArray::make(533, 0)
  b.render(out=r0)
  inspect(buffers_equal(r0, chunks_a[2]), content="true")
  let r1 : FixedArray[Int] = FixedArray::make(533, 0)
  b.render(out=r1)
  inspect(buffers_equal(r1, chunks_a[3]), content="true")
}

///|
test "beat counts dotted quarters across tick boundaries" {
  // One beat = 12 song ticks; the 12th boundary sits at
  // ceil(12 * 960000 / 912) = sample 12632. The song is one 24-tick note,
  // so the whole song is one loop and the transport cannot wrap early.
  let track : @music.Track = {
    instrument: @music.Instrument::celesta(),
    notes: [{ pitch: @music.Pitch::from_midi(midi=69), ticks: 24, }],
  }
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[track],
  )
  let player = Player::new(song~)
  inspect(player.beat(), content="0")
  let pre : FixedArray[Int] = FixedArray::make(12631, 0)
  player.render(out=pre)
  inspect(player.beat(), content="0")
  let one : FixedArray[Int] = FixedArray::make(1, 0)
  player.render(out=one)
  inspect(player.beat(), content="1")
  inspect(player.position_ticks(), content="12")
}

///|
test "an empty song renders silence forever without advancing" {
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[],
  )
  let player = Player::new(song~)
  let out : FixedArray[Int] = FixedArray::make(1000, 5)
  player.render(out~)
  inspect(all_zero(out), content="true")
  inspect(player.position_ticks(), content="0")
  inspect(player.beat(), content="0")
  player.render(out~)
  inspect(all_zero(out), content="true")
}

///|
test "four simultaneous voices clamp into PCM16" {
  let notes : Array[@music.Note] = []
  for _ in 0..<12 {
    notes.push({ pitch: @music.Pitch::from_midi(midi=69), ticks: 4, })
    notes.push({ pitch: None, ticks: 4, })
  }
  let noise : @music.Instrument = {
    name: "Noise",
    waveform: @music.Noise,
    envelope: { attack_ms: 0, decay_ms: 30, sustain: 4096, release_ms: 32, },
    volume: 100,
    vibrato: None,
  }
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[
      { instrument: noise, notes, },
      { instrument: noise, notes, },
      { instrument: noise, notes, },
      { instrument: noise, notes, },
    ],
  ) catch {
    err => abort("noise test song violates four-voice cap: \{err}")
  }
  let player = Player::new(song~)
  // Two tick periods: all four voices (same LFSR seed, so same polarity)
  // sound together and clamp hard on both rails.
  let out : FixedArray[Int] = FixedArray::make(2200, 0)
  player.render(out~)
  let mut lo = out[0]
  let mut hi = out[0]
  for i in 1..<out.length() {
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
test "beats accrue monotonically: 12 elapsed ticks => beat 1, 24 => beat 2" {
  // One beat = 12 song ticks of ELAPSED transport time. The song is one
  // 24-tick note, so the whole song is one loop and the transport cannot
  // wrap early: the 12th boundary sits at ceil(12 * 960000 / 912) = 12632,
  // the 24th (the wrap) at 25264.
  let track : @music.Track = {
    instrument: @music.Instrument::celesta(),
    notes: [{ pitch: @music.Pitch::from_midi(midi=69), ticks: 24, }],
  }
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[track],
  )
  let player = Player::new(song~)
  inspect(player.beat(), content="0")
  let pre : FixedArray[Int] = FixedArray::make(12631, 0)
  player.render(out=pre)
  inspect(player.beat(), content="0")
  let one : FixedArray[Int] = FixedArray::make(1, 0)
  player.render(out=one)
  inspect(player.beat(), content="1")
  inspect(player.position_ticks(), content="12")
  // Render up to the 24th boundary (the loop wrap): the second beat is
  // counted from elapsed ticks, not from landing on a beat-aligned position.
  let more : FixedArray[Int] = FixedArray::make(25264 - 12632, 0)
  player.render(out=more)
  inspect(player.beat(), content="2")
  inspect(player.position_ticks(), content="0")
}

///|
test "a 10-tick looping song counts no beat at its wrap; beat 1 lands after 12 elapsed ticks" {
  // Loop length 10 is not a multiple of the 12-tick beat: the wrap lands on
  // position 0 but only 10 ticks have elapsed, so it must NOT count a beat.
  let track : @music.Track = {
    instrument: @music.Instrument::celesta(),
    notes: [{ pitch: @music.Pitch::from_midi(midi=69), ticks: 10, }],
  }
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[track],
  )
  let player = Player::new(song~)
  // Boundary 10 (the wrap) sits at ceil(10 * 960000 / 912) = 10527.
  let wrap : FixedArray[Int] = FixedArray::make(10527, 0)
  player.render(out=wrap)
  inspect(player.beat(), content="0")
  inspect(player.position_ticks(), content="0")
  // Boundaries 11 and 12: after 12 total elapsed ticks across the wrap the
  // beat counter reaches 1 (at sample 12632, position 2).
  let eleven : FixedArray[Int] = FixedArray::make(11579 - 10527, 0)
  player.render(out=eleven)
  inspect(player.beat(), content="0")
  inspect(player.position_ticks(), content="1")
  let twelve : FixedArray[Int] = FixedArray::make(12632 - 11579, 0)
  player.render(out=twelve)
  inspect(player.beat(), content="1")
  inspect(player.position_ticks(), content="2")
}

///|
test "a player stays deterministic when the caller mutates its authoring arrays" {
  // Song::new snapshots the authoring data, so mutating the arrays after
  // construction can neither change the notes the transport plays nor
  // invalidate the event scratch sized from the snapshot.
  let build : () -> @music.Song = fn() {
    let notes : Array[@music.Note] = [
      { pitch: @music.Pitch::from_midi(midi=69), ticks: 4, },
    ]
    let tracks : Array[@music.Track] = [
      { instrument: @music.Instrument::celesta(), notes, },
    ]
    @music.Song::new(
      meter=@music.Meter::six_eight(),
      tempo=@music.Tempo::standard(),
      tracks~,
    ) catch {
      err => abort("test song violates four-voice cap: \{err}")
    }
  }
  let notes : Array[@music.Note] = [
    { pitch: @music.Pitch::from_midi(midi=69), ticks: 4, },
  ]
  let tracks : Array[@music.Track] = [
    { instrument: @music.Instrument::celesta(), notes, },
  ]
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks~,
  ) catch {
    err => abort("test song violates four-voice cap: \{err}")
  }
  let player = Player::new(song~)
  // Mutate everything the caller still holds: more notes, a second track.
  notes.push({ pitch: None, ticks: 4, })
  notes.push({ pitch: @music.Pitch::from_midi(midi=72), ticks: 4, })
  tracks.push({
    instrument: @music.Instrument::woodwind(),
    notes: [{ pitch: @music.Pitch::from_midi(midi=64), ticks: 4, }],
  })
  let a : FixedArray[Int] = FixedArray::make(4300, 0)
  player.render(out=a)
  // A fresh player over a pristine, identical authoring snapshot must
  // produce the identical stream (4300 samples cross the 4-tick loop wrap).
  let pristine = Player::new(song=build())
  let b : FixedArray[Int] = FixedArray::make(4300, 0)
  pristine.render(out=b)
  inspect(buffers_equal(a, b), content="true")
}

///|
test "render length 0 is a no-op" {
  let player = Player::new(song=dense_song())
  let empty : FixedArray[Int] = []
  player.render(out=empty)
  inspect(player.position_ticks(), content="0")
  inspect(player.beat(), content="0")
}
