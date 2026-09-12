///|
/// Pure state transition for one frame.
///
/// Reads the polled `@input.InputState` snapshot; `update` itself NEVER calls
/// `@input.InputState::advance` — the host loop owns frame boundaries. The
/// receiver is never mutated; a new `State` is returned instead.
///
/// Controls: `Ok` toggles pause on a `just_pressed` edge only; `Up` raises
/// the speed one level and `Down` lowers it, both clamped to 0..=3 and both
/// working whether paused or not. While unpaused the world scrolls
/// `speed.level` pixels this frame and the walker pose advances while the
/// speed is above zero; a paused scene freezes scroll and walker pose while
/// the frame counter keeps counting.
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
    (
      self.scroll + level,
      if level > 0 {
        frame / 8 % 4
      } else {
        self.walker_frame
      },
    )
  }
  { frame, scroll, speed: { level, }, walker_frame, paused, song: self.song, }
}
