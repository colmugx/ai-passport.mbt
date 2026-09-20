///|
/// Primitive operations supplied by one Host sound runtime. This package is
/// an SDK implementation boundary: application packages use `@audio`, never
/// this type.
pub struct SoundRuntime {
  priv play_sound : (UInt, Bool) -> Int?
  priv pause_playback : (Int) -> Unit
  priv resume_playback : (Int) -> Unit
  priv stop_playback : (Int) -> Unit
  priv playback_position_us : (Int) -> Int64?
}

///|
/// Constructs the narrow operation table installed by a Host. Resource IDs
/// and playback handles remain primitive at this boundary; no application
/// type or Host implementation detail crosses it.
pub fn SoundRuntime::new(
  play_sound~ : (UInt, Bool) -> Int?,
  pause_playback~ : (Int) -> Unit,
  resume_playback~ : (Int) -> Unit,
  stop_playback~ : (Int) -> Unit,
  playback_position_us~ : (Int) -> Int64?,
) -> SoundRuntime {
  {
    play_sound,
    pause_playback,
    resume_playback,
    stop_playback,
    playback_position_us,
  }
}

///|
priv struct RuntimeSlot {
  mut runtime : SoundRuntime?
}

///|
let runtime_slot : RuntimeSlot = { runtime: None, }

///|
/// Installs the process-wide Host sound runtime. A Host owns exactly one
/// runtime for the lifetime of an application; replacing it would invalidate
/// every live playback handle, so duplicate installation is a hard error.
pub fn install(runtime : SoundRuntime) -> Unit {
  if runtime_slot.runtime is Some(_) {
    abort("passport sound runtime installed twice")
  }
  runtime_slot.runtime = Some(runtime)
}

///|
fn require_runtime() -> SoundRuntime {
  match runtime_slot.runtime {
    Some(runtime) => runtime
    None => abort("passport sound runtime used before Host initialization")
  }
}

///|
pub fn play(sound_id : UInt, looping : Bool) -> Int? {
  (require_runtime().play_sound)(sound_id, looping)
}

///|
pub fn pause(handle : Int) -> Unit {
  (require_runtime().pause_playback)(handle)
}

///|
pub fn resume_playback(handle : Int) -> Unit {
  (require_runtime().resume_playback)(handle)
}

///|
pub fn stop(handle : Int) -> Unit {
  (require_runtime().stop_playback)(handle)
}

///|
pub fn position(handle : Int) -> Int64? {
  (require_runtime().playback_position_us)(handle)
}
