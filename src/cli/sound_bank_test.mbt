///|
fn sound_input(
  name : String,
  source : String,
  bytes : Array[Byte],
) -> @cli.SoundInput {
  { entry: { name, source, }, pcm: Bytes::from_array(bytes), }
}

///|
test "compile_sounds assigns declaration-order IDs and stable symbols" {
  let compiled = @cli.compile_sounds([
    sound_input("ambient_walk", "assets/ambient_walk.pcm", [1, 0, 2, 0]),
    sound_input("Jump2", "assets/jump.pcm", [3, 0]),
  ])
  inspect(compiled.sounds.length(), content="2")
  assert_eq(compiled.sounds[0].id, 0)
  assert_eq(compiled.sounds[0].name, "ambient_walk")
  assert_eq(compiled.sounds[0].symbol, "AmbientWalk")
  assert_eq(compiled.sounds[0].source, "assets/ambient_walk.pcm")
  assert_eq(compiled.sounds[0].offset, 32)
  assert_eq(compiled.sounds[0].sample_count, 2)
  assert_eq(compiled.sounds[1].id, 1)
  assert_eq(compiled.sounds[1].name, "Jump2")
  assert_eq(compiled.sounds[1].symbol, "Jump2")
  assert_eq(compiled.sounds[1].source, "assets/jump.pcm")
  assert_eq(compiled.sounds[1].offset, 36)
  assert_eq(compiled.sounds[1].sample_count, 1)
}

///|
test "compile_sounds emits deterministic APSB v1 bytes" {
  let inputs = [
    sound_input("ambient_walk", "assets/ambient_walk.pcm", [1, 0, 2, 0]),
    sound_input("jump", "assets/jump.pcm", [3, 0]),
  ]
  let first = @cli.compile_sounds(inputs)
  let second = @cli.compile_sounds(inputs)
  assert_eq(first.bank, second.bank)
  assert_eq(first.bank.to_array().map(fn(byte) { byte.to_int() }), [
    65, 80, 83, 66, 1, 0, 16, 0, 2, 0, 0, 0, 8, 0, 0, 0, 32, 0, 0, 0, 2, 0, 0, 0,
    36, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2, 0, 3, 0,
  ])
}

///|
test "compile_sounds emits a valid deterministic empty bank" {
  let compiled = @cli.compile_sounds([])
  inspect(compiled.sounds.length(), content="0")
  assert_eq(compiled.bank.to_array().map(fn(byte) { byte.to_int() }), [
    65, 80, 83, 66, 1, 0, 16, 0, 0, 0, 0, 0, 8, 0, 0, 0,
  ])
}

///|
test "compile_sounds rejects invalid PCM inputs" {
  let cases = [
    sound_input("empty", "assets/empty.pcm", []),
    sound_input("odd", "assets/odd.pcm", [0]),
    sound_input("wav", "assets/not_pcm.wav", [0, 0]),
  ]
  for input in cases {
    try @cli.compile_sounds([input]) catch {
      @cli.Fail(_) => ()
      _ => fail("expected CliError")
    } noraise {
      _ => fail("expected invalid PCM input to fail")
    }
  }
}

///|
test "compile_sounds rejects invalid or colliding names" {
  let invalid = ["", "2jump", "jump-2", "jump__two", "jump_", "跳跃"]
  for name in invalid {
    try
      @cli.compile_sounds([sound_input(name, "assets/sound.pcm", [0, 0])])
    catch {
      @cli.Fail(_) => ()
      _ => fail("expected CliError")
    } noraise {
      _ => fail("expected invalid sound name to fail")
    }
  }
  try
    @cli.compile_sounds([
      sound_input("ambient_walk", "assets/a.pcm", [0, 0]),
      sound_input("Ambient_walk", "assets/b.pcm", [0, 0]),
    ])
  catch {
    @cli.Fail(message) => inspect(message.contains("collide"), content="true")
    _ => fail("expected CliError")
  } noraise {
    _ => fail("expected generated symbol collision to fail")
  }
  try
    @cli.compile_sounds([
      sound_input("jump", "assets/a.pcm", [0, 0]),
      sound_input("jump", "assets/b.pcm", [0, 0]),
    ])
  catch {
    @cli.Fail(message) =>
      inspect(message.contains("duplicate sound name"), content="true")
    _ => fail("expected CliError")
  } noraise {
    _ => fail("expected duplicate name to fail")
  }
}
