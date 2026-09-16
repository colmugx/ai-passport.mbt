///|
/// Contract, URL and rendering tests for the passport CLI logic. Pure and
/// target-independent: they run on native, js and wasm CI gates.

///|
test "parse_contract accepts the minimal contract" {
  let contract = @cli.parse_contract("{ \"entry\": \"main\" }")
  inspect(contract.entry, content="main")
  debug_inspect(contract.device_entry, content="None")
  inspect(contract.assets.length(), content="0")
}

///|
test "parse_contract accepts entry plus assets" {
  let text =
    #|{
    #|  "entry": "runtime_wasm",
    #|  "assets": [
    #|    { "source": ".passport/assets/tone.pcm", "bundlePath": "assets/tone.pcm", "pcmLoop": true }
    #|  ]
    #|}
  let contract = @cli.parse_contract(text)
  inspect(contract.entry, content="runtime_wasm")
  inspect(contract.assets.length(), content="1")
  inspect(contract.assets[0].source, content=".passport/assets/tone.pcm")
  inspect(contract.assets[0].bundle_path, content="assets/tone.pcm")
  inspect(contract.assets[0].pcm_loop, content="true")
}

///|
test "parse_contract rejects broken documents with clear messages" {
  try @cli.parse_contract("{ not json") catch {
    @cli.Fail(message) =>
      inspect(message, content="passport.json: not valid JSON")
    _ => fail("expected a CliError failure")
  } noraise {
    _ => fail("expected invalid JSON to fail")
  }
  try @cli.parse_contract("{}") catch {
    @cli.Fail(message) =>
      inspect(
        message,
        content="passport.json: missing required field \"entry\" (the application wasm entry package)",
      )
    _ => fail("expected a CliError failure")
  } noraise {
    _ => fail("expected missing entry to fail")
  }
  try @cli.parse_contract("{ \"entry\": 3 }") catch {
    @cli.Fail(message) =>
      inspect(message, content="passport.json: \"entry\" must be a string")
    _ => fail("expected a CliError failure")
  } noraise {
    _ => fail("expected non-string entry to fail")
  }
  try @cli.parse_contract("{ \"entry\": \"main\", \"assets\": [{}] }") catch {
    @cli.Fail(message) =>
      inspect(
        message,
        content="passport.json: asset is missing required field \"source\"",
      )
    _ => fail("expected a CliError failure")
  } noraise {
    _ => fail("expected incomplete asset to fail")
  }
  let two_pcm = "{ \"entry\": \"main\", \"assets\": [ { \"source\": \"a\", \"bundlePath\": \"b\", \"pcmLoop\": true }, { \"source\": \"c\", \"bundlePath\": \"d\", \"pcmLoop\": true } ] }"
  try @cli.parse_contract(two_pcm) catch {
    @cli.Fail(message) =>
      inspect(
        message,
        content="passport.json: at most one asset may set \"pcmLoop\": true (found 2)",
      )
    _ => fail("expected a CliError failure")
  } noraise {
    _ => fail("expected two pcm assets to fail")
  }
}

///|
test "parse_contract accepts a device entry with the same path rules as entry" {
  let contract = @cli.parse_contract(
    "{ \"entry\": \"runtime_wasm\", \"deviceEntry\": \"runtime_native\" }",
  )
  debug_inspect(contract.device_entry, content="Some(\"runtime_native\")")
  try
    @cli.parse_contract(
      "{ \"entry\": \"main\", \"deviceEntry\": \"../escape\" }",
    )
  catch {
    @cli.Fail(_) => ()
    _ => fail("expected an unsafe deviceEntry to fail")
  } noraise {
    _ => fail("expected an unsafe deviceEntry to fail")
  }
  try @cli.parse_contract("{ \"entry\": \"main\", \"deviceEntry\": 7 }") catch {
    @cli.Fail(message) =>
      inspect(
        message,
        content="passport.json: \"deviceEntry\" must be a string",
      )
    _ => fail("expected a CliError failure")
  } noraise {
    _ => fail("expected a non-string deviceEntry to fail")
  }
}

///|
test "parse_contract reads hostDependencies as host-id to path entries" {
  let contract = @cli.parse_contract(
    "{ \"entry\": \"main\", \"hostDependencies\": { \"folotoy-ai-passport\": { \"path\": \"external/folotoy-ai-passport\" } } }",
  )
  debug_inspect(
    @cli.host_dependency_path(contract, "folotoy-ai-passport"),
    content="Some(\"external/folotoy-ai-passport\")",
  )
  debug_inspect(@cli.host_dependency_path(contract, "web"), content="None")
  try
    @cli.parse_contract(
      "{ \"entry\": \"main\", \"hostDependencies\": { \"folotoy-ai-passport\": { \"path\": \"../escape\" } } }",
    )
  catch {
    @cli.Fail(message) =>
      inspect(
        message,
        content="passport.json: hostDependencies[\"folotoy-ai-passport\"].\"path\" contains an unsafe path component",
      )
    _ => fail("expected an unsafe hostDependency path to fail")
  } noraise {
    _ => fail("expected an unsafe hostDependency path to fail")
  }
  try
    @cli.parse_contract(
      "{ \"entry\": \"main\", \"hostDependencies\": { \"folotoy-ai-passport\": {} } }",
    )
  catch {
    @cli.Fail(message) =>
      inspect(
        message,
        content="passport.json: hostDependencies[\"folotoy-ai-passport\"] is missing required field \"path\"",
      )
    _ => fail("expected a hostDependency without path to fail")
  } noraise {
    _ => fail("expected a hostDependency without path to fail")
  }
}

///|
test "entry_url_path derives the generic host parameters" {
  // No audio: the plain entry page.
  inspect(
    @cli.entry_url_path(@cli.parse_contract("{ \"entry\": \"main\" }")),
    content="index.html",
  )
  // One looping PCM asset: the generic URL parameters only.
  inspect(
    @cli.entry_url_path(
      @cli.parse_contract(
        "{ \"entry\": \"main\", \"assets\": [ { \"source\": \"s.pcm\", \"bundlePath\": \"assets/tone.pcm\", \"pcmLoop\": true } ] }",
      ),
    ),
    content="index.html?pcm=./assets/tone.pcm&pcmLoop=1",
  )
  // A plain asset (pcmLoop absent) is materialized but configures no host
  // audio: the minimal contract expresses looping host audio only.
  inspect(
    @cli.entry_url_path(
      @cli.parse_contract(
        "{ \"entry\": \"main\", \"assets\": [ { \"source\": \"s.pcm\", \"bundlePath\": \"assets/once.pcm\" } ] }",
      ),
    ),
    content="index.html",
  )
}

///|
test "percent_encode keeps unreserved path characters and escapes the rest" {
  inspect(@cli.percent_encode("./assets/tone.pcm"), content="./assets/tone.pcm")
  inspect(
    @cli.percent_encode("assets/my tone.pcm"),
    content="assets/my%20tone.pcm",
  )
  inspect(@cli.percent_encode("a&b=c"), content="a%26b%3Dc")
}

///|
test "render_host is deterministic and names the microphone for the wearable" {
  let web = @hosts.find_host("web").unwrap()
  inspect(
    @cli.render_host(web),
    content=@cli.render_host(@hosts.find_host("web").unwrap()),
  )
  let text = @cli.render_host(@hosts.find_host("folotoy-ai-passport").unwrap())
  inspect(text.contains("folotoy-ai-passport"), content="true")
  inspect(text.contains("audio_input"), content="true")
  inspect(text.contains("backend: implemented"), content="true")
  inspect(
    text.contains("normalized PCM16 LE mono 16000 Hz playback asset"),
    content="true",
  )
  // The user-facing backend vocabulary is Host, everywhere. The forbidden
  // terms are assembled from parts so this structural gate never sees them
  // as literals in CLI/host sources.
  let term_a = String::add("bo", "ard")
  let term_b = String::add("prod", "uct")
  inspect(text.to_lower().contains(term_a), content="false")
  inspect(text.to_lower().contains(term_b), content="false")
}

///|
test "known host ids are exact and ordered" {
  inspect(@cli.known_host_ids(), content="web, folotoy-ai-passport")
}

///|
test "require_implemented_host accepts both implemented backends and rejects unknown hosts" {
  inspect(
    @cli.require_implemented_host("folotoy-ai-passport").id,
    content="folotoy-ai-passport",
  )
  try @cli.require_implemented_host("zectrix-note4") catch {
    @cli.Fail(message) =>
      inspect(
        message,
        content="unknown host \"zectrix-note4\" (registered hosts: web, folotoy-ai-passport)",
      )
    _ => fail("expected a CliError failure")
  } noraise {
    _ => fail("expected an unknown host to fail")
  }
  inspect(@cli.require_implemented_host("web").id, content="web")
}

///|
test "moon_mod_scalar reads the common module facts" {
  let text = "name = \"colmugx/ai-passport\"\n\nversion = \"0.0.4\"\n\nsource = \"src\"\n"
  debug_inspect(
    @cli.moon_mod_scalar(text, "name"),
    content="Some(\"colmugx/ai-passport\")",
  )
  debug_inspect(@cli.moon_mod_scalar(text, "source"), content="Some(\"src\")")
  debug_inspect(
    @cli.moon_mod_scalar(text, "version"),
    content="Some(\"0.0.4\")",
  )
  inspect(@cli.moon_mod_scalar(text, "keywords") is Some(_), content="false")
}

///|
test "sdk_dependency_version finds the pinned version" {
  debug_inspect(
    @cli.sdk_dependency_version("import {\n  \"colmugx/ai-passport@0.0.3\",\n}"),
    content="Some(\"0.0.3\")",
  )
  inspect(
    @cli.sdk_dependency_version("import {\n  \"other/mod@1.0\",\n}") is Some(_),
    content="false",
  )
}

///|
test "expected_wasm_artifact follows the moon build layout" {
  let project : @cli.Project = {
    root: "/work/app",
    module_name: "colmugx/app",
    source_dir: "src",
    contract: {
      entry: "main",
      device_entry: None,
      assets: [],
      host_dependencies: [],
    },
  }
  inspect(
    @cli.expected_wasm_artifact(project),
    content="/work/app/_build/wasm/release/build/main/main.wasm",
  )
  let nested : @cli.Project = {
    root: "/work/app",
    module_name: "colmugx/app",
    source_dir: "src",
    contract: {
      entry: "cmd/greeter",
      device_entry: None,
      assets: [],
      host_dependencies: [],
    },
  }
  inspect(
    @cli.expected_wasm_artifact(nested),
    content="/work/app/_build/wasm/release/build/cmd/greeter/greeter.wasm",
  )
}
