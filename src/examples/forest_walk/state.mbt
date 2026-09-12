///|
/// Walking speed in discrete steps; clamped to 0..=3 (0 = standing still).
pub(all) struct Speed {
  level : Int
}

///|
/// The standing-still speed used when scene state is first created.
pub fn Speed::zero() -> Speed {
  { level: 0, }
}

///|
/// All scene state for the walking loop.
///
/// The struct is immutable from the outside: `State::update` returns a new
/// `State` instead of mutating the receiver, so a frame can be redrawn or
/// replayed safely. Fields are private; read them through the accessors.
pub struct State {
  priv frame : Int // monotonically increasing frame counter
  priv scroll : Int // horizontal world scroll offset in pixels
  priv speed : Speed
  priv walker_frame : Int // walker animation frame 0..=3
  priv paused : Bool
  priv song : @music.Song
}

///|
/// Builds one placeholder note of the given duration in eighth notes.
fn note(midi~ : Int, eighths~ : Int) -> @music.Note {
  { pitch: @music.Pitch::from_midi(midi~), eighths, }
}

///|
/// Builds one rest of the given duration in eighth notes.
fn rest(eighths~ : Int) -> @music.Note {
  { pitch: None, eighths, }
}

///|
/// Builds one monophonic voice for the showcase song.
fn showcase_track(
  name~ : String,
  waveform~ : @music.Waveform,
  notes~ : Array[@music.Note],
) -> @music.Track {
  { instrument: { name, waveform, }, notes, }
}

///|
/// Creates the initial scene: standing still, not paused, frame counter at
/// zero, and the four-voice Forest Walk showcase song (docs/MUSIC.md roles:
/// Celesta, Woodwind Lead, Lyrical Strings, Low Strings over 6/8). The
/// four-voice cap holds by construction, so a violation would be a bug and
/// aborts loudly instead of being swallowed.
pub fn State::new() -> State {
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[
      showcase_track(name="Celesta", waveform=@music.Pulse12, notes=[
        note(midi=76, eighths=1),
        rest(eighths=1),
        note(midi=79, eighths=1),
        note(midi=83, eighths=1),
        rest(eighths=2),
      ]),
      showcase_track(name="Woodwind Lead", waveform=@music.Pulse25, notes=[
        note(midi=71, eighths=3),
        rest(eighths=3),
      ]),
      showcase_track(name="Lyrical Strings", waveform=@music.Pulse50, notes=[
        rest(eighths=2),
        note(midi=64, eighths=4),
      ]),
      showcase_track(name="Low Strings", waveform=@music.Triangle, notes=[
        note(midi=40, eighths=3),
        rest(eighths=1),
        note(midi=45, eighths=2),
      ]),
    ],
  ) catch {
    err => abort("showcase song violates four-voice cap: \{err}")
  }
  {
    frame: 0,
    scroll: 0,
    speed: Speed::zero(),
    walker_frame: 0,
    paused: false,
    song,
  }
}

///|
/// Current walking speed.
pub fn State::speed(self : State) -> Speed {
  self.speed
}

///|
/// Whether the scene (and its music) is paused.
pub fn State::paused(self : State) -> Bool {
  self.paused
}

///|
/// Horizontal world scroll offset in pixels.
pub fn State::scroll(self : State) -> Int {
  self.scroll
}

///|
/// Walker animation frame, always 0..=3.
pub fn State::walker_frame(self : State) -> Int {
  self.walker_frame
}

///|
/// Monotonically increasing frame counter; it advances even while paused.
pub fn State::frame(self : State) -> Int {
  self.frame
}

///|
/// The four-voice showcase song driving the scene's music.
pub fn State::song(self : State) -> @music.Song {
  self.song
}
