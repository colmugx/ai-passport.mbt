///|
/// Audio samples fed to the transport per update frame: 16000 Hz / 30 fps.
/// The host preview does not pass real elapsed time deltas yet, so one
/// update is assumed to be exactly one 30 fps frame of audio time.
const FRAME_SAMPLES : Int = 533

///|
/// Pure state transition for one frame.
///
/// Reads the polled `@input.InputState` snapshot; `update` itself NEVER calls
/// `@input.InputState::advance` — the host loop owns frame boundaries. The
/// scene fields are recomputed into a new `State`; the music transport
/// (`clock`/`sequencer`) is one long-lived shared object that this call
/// advances in place while unpaused (read it via `State::sequencer()`).
///
/// Controls: `Ok` toggles pause on a `just_pressed` edge only; `Up` raises
/// the speed one level and `Down` lowers it, both clamped to 0..=3 and both
/// working whether paused or not. While unpaused the world scrolls
/// `speed.level` pixels this frame, the transport pumps `FRAME_SAMPLES` of
/// audio into the clock and steps the sequencer once per elapsed eighth-tick,
/// and the walker pose shifts one weight per large 6/8 beat (`beat % 4`,
/// docs/SHOWCASE.md) while the speed is above zero. A paused scene freezes
/// scroll, walker pose and the whole transport (music pause = transport
/// pause) while the frame counter keeps counting.
pub fn State::update(self : State, input~ : @input.InputState) -> State {
  let frame = self.frame + 1
  let paused = if input.just_pressed(@input.Ok) {
    !self.paused
  } else {
    self.paused
  }
  // Speed keys react even while paused; the level is clamped on every change.
  let up = if input.just_pressed(@input.Up) { 1 } else { 0 }
  let down = if input.just_pressed(@input.Down) { 1 } else { 0 }
  let level = (self.speed.level + up - down).clamp(min=0, max=3)
  let mut beat = self.beat
  let (scroll, walker_frame) = if paused {
    (self.scroll, self.walker_frame)
  } else {
    // Transport advance: convert this frame's audio samples into eighth-note
    // ticks and step the sequencer once per elapsed tick. The app never
    // consumes the NoteOn events (no synth lives in app code; the future
    // host audio backend reads the transport through State::sequencer()),
    // so each step's event list is explicitly discarded.
    let ticks = self.clock.pump(samples=FRAME_SAMPLES)
    for _ in 0..<ticks {
      let _ = self.sequencer.step()
      // A dotted-quarter boundary: one large 6/8 beat every three ticks.
      if self.sequencer.tick() % 3 == 0 {
        beat = beat + 1
      }
    }
    (
      self.scroll + level,
      // One weight shift per large 6/8 beat; standing still holds the pose
      // even though the music (and so the beat) keeps advancing.
      if level > 0 {
        beat % 4
      } else {
        self.walker_frame
      },
    )
  }
  // The sprite sheets and the music transport are shared between states;
  // every scene field is recomputed as before.
  {
    frame,
    scroll,
    speed: { level, },
    walker_frame,
    paused,
    beat,
    clock: self.clock,
    sequencer: self.sequencer,
    song: self.song,
    walker_sheet: self.walker_sheet,
    tree_sheets: self.tree_sheets,
  }
}
