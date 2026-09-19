///|
/// Contract hardening: entry and asset paths must stay relative to the
/// module, so no parse input can escape or overwrite bundle-owned files.
test "contract rejects non-relative or traversing entry paths" {
  let cases = [
    "entry = \"/main\"", "entry = \"../main\"", "entry = \"main/../other\"", "entry = \"main\\\\other\"",
  ]
  for text in cases {
    try @cli.parse_contract(text) catch {
      @cli.Fail(_) => ()
      _ => fail("expected CliError")
    } noraise {
      _ => fail("expected unsafe entry to fail")
    }
  }
}

///|
test "contract rejects unsafe asset paths" {
  let cases = [
    "entry = \"main\"\n\n[[assets]]\nsource = \"../secret\"\nbundlePath = \"assets/a\"",
    "entry = \"main\"\n\n[[assets]]\nsource = \"assets/a\"\nbundlePath = \"../escape\"",
    "entry = \"main\"\n\n[[assets]]\nsource = \"assets/a\"\nbundlePath = \"index.html\"",
    "entry = \"main\"\n\n[[assets]]\nsource = \"assets/a\"\nbundlePath = \"sounds.bank\"",
  ]
  for text in cases {
    try @cli.parse_contract(text) catch {
      @cli.Fail(_) => ()
      _ => fail("expected CliError")
    } noraise {
      _ => fail("expected unsafe asset path to fail")
    }
  }
}

///|
test "contract rejects duplicate bundle destinations" {
  let text =
    #|entry = "main"
    #|
    #|[[assets]]
    #|source = "assets/a"
    #|bundlePath = "assets/shared"
    #|
    #|[[assets]]
    #|source = "assets/b"
    #|bundlePath = "assets/shared"
  try @cli.parse_contract(text) catch {
    @cli.Fail(message) =>
      inspect(message.contains("duplicate asset"), content="true")
    _ => fail("expected CliError")
  } noraise {
    _ => fail("expected duplicate destination to fail")
  }
}

///|
test "contract parses a no-audio project without an assets field" {
  let contract = @cli.parse_contract("entry = \"main\"")
  inspect(contract.assets.length(), content="0")
  inspect(contract.entry, content="main")
}

///|
test "contract parses an explicitly empty asset list" {
  let contract = @cli.parse_contract("entry = \"main\"\nassets = []")
  inspect(contract.assets.length(), content="0")
}

///|
test "contract parses independent sound resources in declaration order" {
  let text =
    #|entry = "main"
    #|
    #|[[sounds]]
    #|name = "ambient_walk"
    #|source = "assets/ambient_walk.pcm"
    #|
    #|[[sounds]]
    #|name = "jump"
    #|source = "assets/jump.pcm"
  let contract = @cli.parse_contract(text)
  inspect(contract.sounds.length(), content="2")
  assert_eq(contract.sounds[0].name, "ambient_walk")
  assert_eq(contract.sounds[0].source, "assets/ambient_walk.pcm")
  assert_eq(contract.sounds[1].name, "jump")
  assert_eq(contract.sounds[1].source, "assets/jump.pcm")
}

///|
test "contract rejects duplicate sound names and unsafe sources" {
  let duplicate =
    #|entry = "main"
    #|[[sounds]]
    #|name = "jump"
    #|source = "assets/a.pcm"
    #|[[sounds]]
    #|name = "jump"
    #|source = "assets/b.pcm"
  try @cli.parse_contract(duplicate) catch {
    @cli.Fail(message) =>
      inspect(message.contains("duplicate sound name"), content="true")
    _ => fail("expected CliError")
  } noraise {
    _ => fail("expected duplicate sound name to fail")
  }
  try
    @cli.parse_contract(
      "entry = \"main\"\n[[sounds]]\nname = \"jump\"\nsource = \"../jump.pcm\"",
    )
  catch {
    @cli.Fail(_) => ()
    _ => fail("expected CliError")
  } noraise {
    _ => fail("expected unsafe sound source to fail")
  }
}

///|
test "contract rejects playback behavior and unknown sound fields" {
  for field in ["loop", "autoplay", "volume", "channel", "pcmLoop"] {
    let text = "entry = \"main\"\n[[sounds]]\nname = \"jump\"\nsource = \"assets/jump.pcm\"\n\{field} = true"
    try @cli.parse_contract(text) catch {
      @cli.Fail(message) => {
        inspect(message.contains("not supported"), content="true")
        inspect(message.contains(field), content="true")
      }
      _ => fail("expected CliError")
    } noraise {
      _ => fail("expected unsupported sound field to fail")
    }
  }
}
