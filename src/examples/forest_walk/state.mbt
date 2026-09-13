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
/// The one exception is the music transport (`clock` and `sequencer`): it is
/// one long-lived object shared by every `State` value, advanced in place by
/// `update` while unpaused and observable through `State::sequencer()` so the
/// host audio backend can render the `NoteOn` events the app itself ignores.
/// Fields are private; read them through the accessors.
pub struct State {
  priv frame : Int // monotonically increasing frame counter
  priv scroll : Int // horizontal world scroll offset in pixels
  priv speed : Speed
  priv walker_frame : Int // walker animation frame 0..=3
  priv paused : Bool
  priv beat : Int // dotted-quarter beat counter (one per large 6/8 beat)
  priv clock : @music.TickClock // shared transport: audio samples -> ticks
  priv sequencer : @music.Sequencer // shared transport: song -> NoteOn events
  priv song : @music.Song
  priv walker_sheet : @graphics.SpriteSheet // built once in State::new
  priv tree_sheets : Array[@graphics.SpriteSheet] // built once in State::new
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
  // The transport is built once from the finished song: the clock converts
  // audio samples to eighth-ticks at the song's own tempo (76 dotted-quarter
  // BPM for `Tempo::standard()`), the sequencer loops the whole song.
  {
    frame: 0,
    scroll: 0,
    speed: Speed::zero(),
    walker_frame: 0,
    paused: false,
    beat: 0,
    clock: @music.TickClock::new(
      sample_rate=@audio.SAMPLE_RATE,
      dotted_quarter_bpm=song.tempo.dotted_quarter_bpm,
    ),
    sequencer: @music.Sequencer::new(song~),
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
/// The music transport playing the showcase song: one long-lived sequencer
/// shared by every `State` value. `State::update` steps it once per elapsed
/// eighth-tick while unpaused; the host audio backend reads it to render the
/// `NoteOn` events the app itself never consumes.
pub fn State::sequencer(self : State) -> @music.Sequencer {
  self.sequencer
}

///|
/// Dotted-quarter beat counter: one increment per large 6/8 beat (every
/// three eighth-ticks of transport time), per docs/SHOWCASE.md. It advances
/// only while the scene is unpaused and freezes with the music when paused.
pub fn State::beat(self : State) -> Int {
  self.beat
}
