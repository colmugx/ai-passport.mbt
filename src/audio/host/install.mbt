///|
/// Installs the primitive sound operations supplied by one SDK-owned Host.
/// Application packages must not import this Host-only adapter.
pub fn install(
  play_sound~ : (UInt, Bool) -> Int?,
  pause_playback~ : (Int) -> Unit,
  resume_playback~ : (Int) -> Unit,
  stop_playback~ : (Int) -> Unit,
  playback_position_us~ : (Int) -> Int64?,
) -> Unit {
  @sound_runtime.install(
    @sound_runtime.SoundRuntime::new(
      play_sound~,
      pause_playback~,
      resume_playback~,
      stop_playback~,
      playback_position_us~,
    ),
  )
}
