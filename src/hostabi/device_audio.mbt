///|
/// Absolute desired audio-output facts crossing into the C music transport.
/// The portable App owns every control semantic; this adapter only mirrors
/// state — the device-side analogue of the wasm path's direct
/// `host_set_volume` / `host_set_muted` imports. The transport itself
/// applies the state in its music task between bounded PCM writes.

///|
/// Remembers the last audio-output state mirrored to the transport. Seed it
/// from the startup facts the transport already received (the App's initial
/// output, or the device's existing silent startup facts when the App had
/// none), so a freshly created mirror crosses no redundant write.
pub struct DeviceAudioMirror {
  mut applied_volume : Int
  mut applied_muted : Bool
}

///|
pub fn DeviceAudioMirror::new(
  initial_volume~ : Int,
  initial_muted~ : Bool,
) -> DeviceAudioMirror {
  { applied_volume: initial_volume, applied_muted: initial_muted, }
}

///|
/// Mirrors the App's absolute desired output to the transport when it
/// changed. Call it once per rendered frame, after the App has applied any
/// latched button edges, so one delivered press crosses into C at most
/// once. Identical state never reaches the transport (the music task skips
/// redundant codec writes on top of that). The muted flag crosses as the C
/// integers 1 (muted) / 0 (audible); that encoding stays inside this
/// adapter.
pub fn DeviceAudioMirror::sync(
  self : DeviceAudioMirror,
  volume : Int,
  muted~ : Bool,
) -> Unit {
  if volume != self.applied_volume || muted != self.applied_muted {
    music_set_output(volume, if muted { 1 } else { 0 })
    self.applied_volume = volume
    self.applied_muted = muted
  }
}
