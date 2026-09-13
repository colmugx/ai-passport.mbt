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
/// The transport starts ON tick 0: the first unpaused render fires the
/// tick-0 note starts (the sequencer's arrival at tick 0) before rendering
/// its first sample, so a song that begins with a note is audible from
/// output sample 0, shaped only by the instrument's own attack envelope —
/// there is no one-tick pre-roll. Every later tick boundary then fires the
/// note-starts landing exactly on it, including the loop wrap, which lands
/// on `loop_start` and re-fires the note-starts that begin there.
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
///   // The tick-0 note is audible from the very first sample (the celesta
///   // plucks at full scale instantly).
///   inspect(out[0], content="12000")
/// }
/// ```
pub struct Player {
  priv clock : @music.TickClock
  priv sequencer : @music.Sequencer
  priv synth : Synth
  priv beat_ticks : Int // song ticks per musical beat (dotted quarter)
  /// Song ticks of transport time elapsed since construction, counted from
  /// actual TickClock boundaries for a nonempty song — including loop wraps —
  /// and independent of the wrapped position. The single authority for
  /// `beat()`.
  priv mut elapsed_ticks : Int
  /// Preallocated note-start slots handed to `step_into` on every arrival —
  /// the realtime path never allocates. One slot per song track (at most
  /// four).
  priv events : FixedArray[@music.NoteOn?]
  priv mut started : Bool // tick-0 arrival not fired yet
  priv mut paused : Bool
}

///|
/// Builds a player for `song` at the 16000 Hz baseline. The transport clock
/// uses the song's own tempo and tick resolution; the whole song is the
/// loop region. The transport is parked on tick 0 with its note starts
/// unfired: the first unpaused render fires them at output sample 0.
pub fn Player::new(song~ : @music.Song) -> Player {
  {
    clock: @music.TickClock::new(
      sample_rate=SAMPLE_RATE,
      dotted_quarter_bpm=song.tempo().dotted_quarter_bpm,
      ticks_per_eighth=song.ticks_per_eighth(),
    ),
    sequencer: @music.Sequencer::new(song~),
    synth: Synth::new(),
    beat_ticks: 3 * song.ticks_per_eighth(),
    events: FixedArray::make(song.track_count(), None),
    started: false,
    elapsed_ticks: 0,
    paused: false,
  }
}

///|
/// Renders the next `out.length()` samples of 16000 Hz signed PCM16 mono,
/// mixing up to four voices and clamping into [-32768, 32767]. While
/// paused, `render` outputs silence and advances nothing — note, loop and
/// transport state all resume exactly where they were (a pause before the
/// first unpaused render defers the tick-0 start instead of skipping it).
/// Length 0 is a no-op. The per-sample path allocates nothing.
///
/// Note starts are triggered with an exact phase-aware gate
/// (`TickClock::ticks_to_samples_exact`): a note of `ticks` song ticks
/// releases exactly on the tick boundary `ticks` ticks after its start,
/// whatever fractional carry the clock holds.
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
  if !self.started {
    // The transport starts on tick 0: fire its note-starts before the first
    // sample so they are audible from output sample 0. The beat counter
    // stays put — zero beats have elapsed.
    self.started = true
    self.fire_arrival()
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
    let elapsed = self.clock.pump(samples=to_boundary)
    if elapsed != 1 {
      abort(
        "Player::render: expected one tick at a clock boundary, got \{elapsed}",
      )
    }
    pos += to_boundary
    // Clock time is the authority for beats. A one-tick loop lands back on
    // position 0 at every boundary, so position cannot reveal elapsed time.
    // Empty songs have no musical transport and keep beat() at zero.
    if self.sequencer.length() > 0 {
      self.elapsed_ticks += elapsed
    }
    // Tick boundary: step the transport and trigger the note starts at
    // exactly this sample offset.
    self.fire_arrival()
  }
}

///|
/// Steps the sequencer across one arrival (a tick boundary, the initial
/// tick 0, or a loop wrap) and triggers every reported note-start on the
/// voice matching its track index, with its exact phase-aware gate. Uses
/// only the preallocated event slots — no allocation. The sequencer owns
/// position and events; elapsed clock ticks are counted in `render` after
/// pumping a real sample boundary. The initial tick-0 arrival counts zero.
fn Player::fire_arrival(self : Player) -> Unit {
  let count = self.sequencer.step_into(self.events)
  for i in 0..<count {
    match self.events[i] {
      Some(event) =>
        self.synth.trigger(
          voice=event.track,
          on=event,
          gate_samples=self.clock.ticks_to_samples_exact(ticks=event.ticks),
        )
      None => () // unreachable: slots below count are always Some
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
/// `3 * ticks_per_eighth` monotonically elapsed transport ticks, independent
/// of the loop position: a loop whose length is not a beat multiple counts
/// no beat at its wrap, and beats keep accruing across wraps (12 elapsed
/// ticks => beat 1, 24 => beat 2, whatever the loop length). The initial
/// tick-0 arrival counts nothing (zero beats have elapsed at the start), and
/// pausing freezes the count with everything else. Graphics reads this to
/// sync animation to the music.
pub fn Player::beat(self : Player) -> Int {
  self.elapsed_ticks / self.beat_ticks
}
