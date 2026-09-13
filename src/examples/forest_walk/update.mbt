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
/// (`player`) is one long-lived shared object that this call feeds one frame
/// of audio to while unpaused (read it via `State::player()`).
///
/// Controls: `Ok` toggles pause on a `just_pressed` edge only; `Up` raises
/// the speed one level and `Down` lowers it, both clamped to 0..=3 and both
/// working whether paused or not. While unpaused the world scrolls
/// `speed.level` pixels this frame, the transport renders `FRAME_SAMPLES`
/// of audio through the SDK player (whose beat counter advances exactly one
/// beat per dotted quarter), and the walker pose shifts one weight per
/// large 6/8 beat (`beat % 4`,
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
  let (scroll, walker_frame) = if paused {
    (self.scroll, self.walker_frame)
  } else {
    // Transport advance: render this frame's audio through the SDK player.
    // The player owns the authoritative music clock (sample-accurate note
    // scheduling), so app code never pumps a clock or steps a sequencer; it
    // only feeds the frame's sample count and reads beat/paused back. On
    // device, the audio callback would call player.render instead and the
    // frame loop would only read the transport position. The scratch buffer
    // is one frame of PCM reused every update; the app itself has no audio
    // sink to send it to.
    self.player.render(out=self.scratch)
    let beat = self.player.beat()
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
    player: self.player,
    scratch: self.scratch,
    song: self.song,
    walker_sheet: self.walker_sheet,
    tree_sheets: self.tree_sheets,
  }
}
