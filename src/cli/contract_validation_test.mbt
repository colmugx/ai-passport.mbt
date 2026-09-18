///|
/// Contract hardening: entry and asset paths must stay relative to the
/// module, so no parse input can escape or overwrite bundle-owned files.
test "contract rejects non-relative or traversing entry paths" {
  let cases = [
    "entry = \"/main\"",
    "entry = \"../main\"",
    "entry = \"main/../other\"",
    "entry = \"main\\\\other\"",
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
