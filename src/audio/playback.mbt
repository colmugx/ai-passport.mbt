///|
/// One actual playback instance created from a `Sound`.
///
/// The handle is deliberately opaque. Playing the same `Sound` twice creates
/// two independent `Playback` values; control and position operations always
/// target one playback, never the resource as a whole.
pub struct Playback {
  priv handle : Int
}

///|
/// Starts one playback of `sound`. `looping` is behavior of this playback
/// instance, not resource metadata.
///
/// Returns `None` when the Host cannot allocate another playback slot. The
/// Host never steals or stops an unrelated playback to make room.
///
/// ```mbt nocheck
/// let music = @audio.play(@sounds.ForestWalk, looping=true)
///
/// let hit1 = @audio.play(@sounds.Hit)
///
/// let hit2 = @audio.play(@sounds.Hit)
/// ```
pub fn[T : Sound] play(sound : T, looping? : Bool = false) -> Playback? {
  match @sound_runtime.play(sound.resource_id(), looping) {
    Some(handle) => Some({ handle, })
    None => None
  }
}

///|
/// Pauses one playback instance. Other playbacks of the same `Sound` are
/// unaffected.
pub fn pause(playback : Playback) -> Unit {
  @sound_runtime.pause(playback.handle)
}

///|
/// Resumes one paused playback instance.
#alias(resume, visibility="pub")
fn resume_playback(playback : Playback) -> Unit {
  @sound_runtime.resume_playback(playback.handle)
}

///|
/// Stops one playback instance.
pub fn stop(playback : Playback) -> Unit {
  @sound_runtime.stop(playback.handle)
}

///|
/// Returns the playback's current position in microseconds, or `None` when
/// the Host no longer has a live position for this handle.
pub fn position(playback : Playback) -> Int64? {
  @sound_runtime.position(playback.handle)
}
