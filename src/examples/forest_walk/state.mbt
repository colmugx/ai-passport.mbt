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
/// The scene fields are immutable from the outside: `State::update` returns a
/// new `State` instead of rewriting them, so a frame can be redrawn safely.
/// The one exception is the music transport (`player`): it is one long-lived
/// object shared by every `State` value, advanced in place by `update` while
/// unpaused (it renders each frame's audio through the SDK `Player`, whose
/// sample-accurate transport owns the music clock) and observable through
/// `State::player()`. Fields are private; read them through the accessors.
pub struct State {
  priv frame : Int // monotonically increasing frame counter
  priv scroll : Int // horizontal world scroll offset in pixels
  priv speed : Speed
  priv walker_frame : Int // walker animation frame 0..=3
  priv paused : Bool
  priv player : @audio.Player // shared transport: owns the music clock
  priv scratch : FixedArray[Int] // one frame of PCM, reused every update
  priv song : @music.Song
  priv walker_sheet : @graphics.SpriteSheet // built once in State::new
  priv tree_sheets : Array[@graphics.SpriteSheet] // built once in State::new
}

///|
/// Builds one placeholder note of the given duration in song ticks
/// (4 ticks per eighth note at the default v0.1 resolution).
fn note(midi~ : Int, ticks~ : Int) -> @music.Note {
  { pitch: @music.Pitch::from_midi(midi~), ticks, }
}

///|
/// Builds one rest of the given duration in song ticks.
fn rest(ticks~ : Int) -> @music.Note {
  { pitch: None, ticks, }
}

///|
/// Builds one monophonic voice for the showcase song from one of the SDK
/// instrument presets (whose role names are the showcase roles).
fn showcase_track(
  instrument~ : @music.Instrument,
  notes~ : Array[@music.Note],
) -> @music.Track {
  { instrument, notes, }
}

///|
/// Creates the initial scene: standing still, not paused, frame counter and
/// beat counter at zero, the four-voice Forest Walk showcase song (docs/
/// MUSIC.md roles: Celesta, Woodwind Lead, Lyrical Strings, Low Strings over
/// 6/8) and its transport built once from that song at `@audio.SAMPLE_RATE`.
/// The four-voice cap holds by construction, so a violation would be a bug
/// and aborts loudly instead of being swallowed.
pub fn State::new() -> State {
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[
      showcase_track(instrument=@music.Instrument::celesta(), notes=[
        note(midi=76, ticks=4),
        rest(ticks=4),
        note(midi=79, ticks=4),
        note(midi=83, ticks=4),
        rest(ticks=8),
      ]),
      showcase_track(instrument=@music.Instrument::woodwind(), notes=[
        note(midi=71, ticks=12),
        rest(ticks=12),
      ]),
      showcase_track(instrument=@music.Instrument::strings(), notes=[
        rest(ticks=8),
        note(midi=64, ticks=16),
      ]),
      showcase_track(instrument=@music.Instrument::low_strings(), notes=[
        note(midi=40, ticks=12),
        rest(ticks=4),
        note(midi=45, ticks=8),
      ]),
    ],
  ) catch {
    err => abort("showcase song violates four-voice cap: \{err}")
  }
  // The transport is built once from the finished song: the player owns the
  // clock (76 dotted-quarter BPM, 4 ticks per eighth) and loops the whole
  // song, driving the synth from the sequencer's note starts.
  {
    frame: 0,
    scroll: 0,
    speed: Speed::zero(),
    walker_frame: 0,
    paused: false,
    player: @audio.Player::new(song~),
    scratch: FixedArray::make(FRAME_SAMPLES, 0),
    song,
    walker_sheet: build_walker_sheet(),
    tree_sheets: [
      build_tree_sheet(width=8, height=14),
      build_tree_sheet(width=10, height=16),
      build_tree_sheet(width=12, height=20),
    ],
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
/// The walker's four-frame sprite sheet: four 12x20 placeholder poses
/// generated procedurally, one weight-shift beat each.
pub fn State::walker_sheet(self : State) -> @graphics.SpriteSheet {
  self.walker_sheet
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

///|
/// The music transport playing the showcase song: one long-lived SDK
/// `Player` shared by every `State` value. `State::update` renders each
/// unpaused frame's audio through it; a device backend would instead call
/// `player.render` from its audio callback with real sample counts.
pub fn State::player(self : State) -> @audio.Player {
  self.player
}

///|
/// Dotted-quarter beat counter: one increment per large 6/8 beat (every
/// `3 * ticks_per_eighth` song ticks of transport time), per
/// docs/SHOWCASE.md, counted by the player's transport. It advances only
/// while the scene is unpaused and freezes with the music when paused.
pub fn State::beat(self : State) -> Int {
  self.player.beat()
}
