///|
priv struct FakeSoundRuntime {
  mut next_handle : Int
  capacity : Int
  plays : Array[(UInt, Bool, Int)]
  paused : Array[Int]
  resumed : Array[Int]
  stopped : Map[Int, Bool]
}

///|
fn FakeSoundRuntime::new(capacity : Int) -> FakeSoundRuntime {
  { next_handle: 1, capacity, plays: [], paused: [], resumed: [], stopped: {}, }
}

///|
fn FakeSoundRuntime::operations(
  self : FakeSoundRuntime,
) -> @sound_runtime.SoundRuntime {
  @sound_runtime.SoundRuntime::new(
    play_sound=fn(sound_id : UInt, looping : Bool) {
      if self.plays.length() >= self.capacity {
        return None
      }
      let handle = self.next_handle
      self.next_handle += 1
      self.plays.push((sound_id, looping, handle))
      Some(handle)
    },
    pause_playback=fn(handle) { self.paused.push(handle) },
    resume_playback=fn(handle) { self.resumed.push(handle) },
    stop_playback=fn(handle) { self.stopped[handle] = true },
    playback_position_us=fn(handle) {
      if self.stopped.contains(handle) {
        None
      } else {
        Some(handle.to_int64() * 1000L)
      }
    },
  )
}

///|
enum PlaybackTestSound {
  ForestWalk
  Hit
}

///|
impl Sound for PlaybackTestSound with fn resource_id(self : PlaybackTestSound) -> UInt {
  match self {
    ForestWalk => 4U
    Hit => 9U
  }
}

///|
test "sound playback is instance-scoped and capacity failure is explicit" {
  let fake = FakeSoundRuntime::new(3)
  @sound_runtime.install(fake.operations())
  let music = play(PlaybackTestSound::ForestWalk, looping=true).unwrap()
  let hit1 = play(PlaybackTestSound::Hit).unwrap()
  let hit2 = play(PlaybackTestSound::Hit).unwrap()
  assert_true(play(PlaybackTestSound::Hit) is None)
  debug_inspect(
    fake.plays,
    content="[(4, true, 1), (9, false, 2), (9, false, 3)]",
  )
  debug_inspect(position(music), content="Some(1000)")
  debug_inspect(position(hit1), content="Some(2000)")
  debug_inspect(position(hit2), content="Some(3000)")
  pause(music)
  resume_playback(music)
  stop(music)
  debug_inspect(fake.paused, content="[1]")
  debug_inspect(fake.resumed, content="[1]")
  debug_inspect(position(music), content="None")
  debug_inspect(position(hit1), content="Some(2000)")
}
