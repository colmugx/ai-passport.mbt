///|
/// Shared Host-side adapter for installing primitive Sound operations. Web
/// and device supply different ABI functions but use this exact boundary.
#warnings("-unused_value")
fn install_sound_runtime(
  play_sound~ : (UInt, Bool) -> Int?,
  pause_playback~ : (Int) -> Unit,
  resume_playback~ : (Int) -> Unit,
  stop_playback~ : (Int) -> Unit,
  playback_position_us~ : (Int) -> Int64?,
) -> Unit {
  @sound_host.install(
    play_sound~,
    pause_playback~,
    resume_playback~,
    stop_playback~,
    playback_position_us~,
  )
}
