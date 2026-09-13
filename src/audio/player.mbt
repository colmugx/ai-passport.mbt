///|
/// SDK-owned music transport: Song -> TickClock -> Sequencer -> NoteOn ->
/// Synth -> PCM16.
///
/// The player owns the authoritative music clock. Musical events fire at
/// their exact sample position INSIDE each output buffer: `render` segments
/// the buffer at transport tick boundaries — render the synth up to the
/// boundary, step the sequencer, trigger the new notes, continue with the
/// rest — never rendering a whole buffer and only then processing elapsed
/// ticks. One 4096-sample render therefore produces exactly the same PCM as
/// sixteen 256-sample renders, whatever the tick boundaries.
///
/// Graphics and app code only read `beat()` / `position_ticks()` / `paused()`
/// to sync animation; nothing else advances the transport. The audio
/// callback or task of a backend calls `render` with the actual sample count
/// it needs — the frame loop never does.
///
/// # Example
/// ```mbt check
/// test {
///   let track : @music.Track = {
///     instrument: @music.Instrument::celesta(),
///     notes: [{ pitch: @music.Pitch::from_midi(midi=69), ticks: 4, }],
///   }
///   let song = @music.Song::new(
///     meter=@music.Meter::six_eight(),
///     tempo=@music.Tempo::standard(),
///     tracks=[track],
///   )
///   let player = Player::new(song~)
///   let out : FixedArray[Int] = FixedArray::make(256, 0)
///   player.render(out~)
///   // Before the first tick boundary the player renders silence.
///   inspect(out[255], content="0")
/// }
/// ```
pub struct Player {
  priv clock : @music.TickClock
  priv sequencer : @music.Sequencer
  priv synth : Synth
  priv beat_ticks : Int // song ticks per musical beat (dotted quarter)
  priv mut beats : Int
  priv mut paused : Bool
}

///|
/// Builds a player for `song` at the 16000 Hz baseline. The transport clock
/// uses the song's own tempo and tick resolution; the whole song is the
/// loop region.
pub fn Player::new(song~ : @music.Song) -> Player {
  {
    clock: @music.TickClock::new(
      sample_rate=SAMPLE_RATE,
      dotted_quarter_bpm=song.tempo.dotted_quarter_bpm,
      ticks_per_eighth=song.ticks_per_eighth,
    ),
    sequencer: @music.Sequencer::new(song~),
    synth: Synth::new(),
    beat_ticks: 3 * song.ticks_per_eighth,
    beats: 0,
    paused: false,
  }
}

///|
/// Renders the next `out.length()` samples of 16000 Hz signed PCM16 mono,
/// mixing up to four voices and clamping into [-32768, 32767]. While
/// paused, `render` outputs silence and advances nothing — note, loop and
/// transport state all resume exactly where they were. Length 0 is a no-op.
/// The per-sample path allocates nothing.
///
/// Note starts are triggered with a gate of the note's full length in
/// samples (floored, at least one sample), on the voice matching the
/// note's track index.
pub fn Player::render(self : Player, out~ : FixedArray[Int]) -> Unit {
  let n = out.length()
  if n == 0 {
    return
  }
  if self.paused {
    for i in 0..<n {
      out[i] = 0
    }
    return
  }
  let mut pos = 0
  while pos < n {
    let to_boundary = self.clock.samples_to_next_tick()
    let remaining = n - pos
    if remaining < to_boundary {
      // The buffer ends before the next tick boundary: render the rest and
      // let the boundary fire inside a later call.
      self.synth.render_range(out~, offset=pos, len=remaining)
      let _ = self.clock.pump(samples=remaining)
      return
    }
    self.synth.render_range(out~, offset=pos, len=to_boundary)
    let _ = self.clock.pump(samples=to_boundary)
    pos += to_boundary
    // Tick boundary: step the transport and trigger the note starts at
    // exactly this sample offset.
    let before = self.sequencer.tick()
    for ev in self.sequencer.step() {
      let gate = self.clock.ticks_to_samples(ticks=ev.ticks)
      self.synth.trigger(
        voice=ev.track,
        on=ev,
        gate_samples=if gate < 1 { 1 } else { gate },
      )
    }
    let after = self.sequencer.tick()
    // A musical beat (dotted quarter) elapses whenever the transport lands
    // on a beat boundary — including the loop wrap back onto tick 0. An
    // idle sequencer (empty song) never moves, so it never counts.
    if after != before && after % self.beat_ticks == 0 {
      self.beats += 1
    }
  }
}

///|
/// Freezes the transport: subsequent renders output silence, note and loop
/// state are preserved, and `position_ticks()` stays put.
pub fn Player::pause(self : Player) -> Unit {
  self.paused = true
}

///|
/// Resumes from the exact musical position the transport was paused at.
/// (Named `unpause` because `resume` is a reserved word on this toolchain.)
pub fn Player::unpause(self : Player) -> Unit {
  self.paused = false
}

///|
/// Whether the transport is currently paused.
pub fn Player::paused(self : Player) -> Bool {
  self.paused
}

///|
/// Current transport position in song ticks, always in `[0, length)` of the
/// loop region.
pub fn Player::position_ticks(self : Player) -> Int {
  self.sequencer.tick()
}

///|
/// Dotted-quarter beats elapsed since construction — one per
/// `3 * ticks_per_eighth` song ticks, monotonic across loop wraps. Graphics
/// reads this to sync animation to the music.
pub fn Player::beat(self : Player) -> Int {
  self.beats
}
