///|
enum TestSound {
  Hit
}

///|
impl Sound for TestSound with fn resource_id(self : TestSound) -> UInt {
  match self {
    Hit => 7U
  }
}

///|
test "generated-style sound enums implement the open Sound contract" {
  let sound : &@audio.Sound = TestSound::Hit
  inspect(sound.resource_id(), content="7")
}
