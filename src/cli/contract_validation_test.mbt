///|
/// Focused contract hardening tests. These cases previously reached raw
/// filesystem joins in the CLI and could escape or overwrite bundle-owned
/// files.
test "contract rejects non-relative or traversing entry paths" {
  let cases = [
    "{ \"entry\": \"/main\" }", "{ \"entry\": \"../main\" }", "{ \"entry\": \"main/../other\" }",
    "{ \"entry\": \"main\\\\other\" }",
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
    "{ \"entry\": \"main\", \"assets\": [ { \"source\": \"../secret\", \"bundlePath\": \"assets/a\" } ] }",
    "{ \"entry\": \"main\", \"assets\": [ { \"source\": \"assets/a\", \"bundlePath\": \"../escape\" } ] }",
    "{ \"entry\": \"main\", \"assets\": [ { \"source\": \"assets/a\", \"bundlePath\": \"index.html\" } ] }",
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
  let text = "{ \"entry\": \"main\", \"assets\": [ { \"source\": \"assets/a\", \"bundlePath\": \"assets/shared\" }, { \"source\": \"assets/b\", \"bundlePath\": \"assets/shared\" } ] }"
  try @cli.parse_contract(text) catch {
    @cli.Fail(message) =>
      inspect(message.contains("duplicate asset"), content="true")
    _ => fail("expected CliError")
  } noraise {
    _ => fail("expected duplicate destination to fail")
  }
}
