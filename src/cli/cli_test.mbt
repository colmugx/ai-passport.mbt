///|
/// Contract, URL and rendering tests for the passport CLI logic. Pure and
/// target-independent: they run on native, js and wasm CI gates.

///|
test "parse_contract accepts the minimal contract" {
  let contract = @cli.parse_contract("entry = \"main\"")
  inspect(contract.entry, content="main")
  debug_inspect(contract.device_entry, content="None")
  inspect(contract.assets.length(), content="0")
  inspect(contract.sounds.length(), content="0")
}

///|
test "parse_contract accepts entry plus assets" {
  let text =
    #|entry = "runtime_wasm"
    #|
    #|[[assets]]
    #|source = "assets/map.bin"
    #|bundlePath = "assets/map.bin"
  let contract = @cli.parse_contract(text)
  inspect(contract.entry, content="runtime_wasm")
  inspect(contract.assets.length(), content="1")
  inspect(contract.assets[0].source, content="assets/map.bin")
  inspect(contract.assets[0].bundle_path, content="assets/map.bin")
  inspect(contract.sounds.length(), content="0")
}

///|
test "parse_contract rejects broken documents with clear messages" {
  try @cli.parse_contract("entry = [") catch {
    @cli.Fail(message) =>
      inspect(message, content="passport.toml: not valid TOML")
    _ => fail("expected a CliError failure")
  } noraise {
    _ => fail("expected invalid TOML to fail")
  }
  try @cli.parse_contract("") catch {
    @cli.Fail(message) =>
      inspect(
        message,
        content="passport.toml: missing required field \"entry\" (the application wasm entry package)",
      )
    _ => fail("expected a CliError failure")
  } noraise {
    _ => fail("expected missing entry to fail")
  }
  try @cli.parse_contract("entry = 3") catch {
    @cli.Fail(message) =>
      inspect(message, content="passport.toml: \"entry\" must be a string")
    _ => fail("expected a CliError failure")
  } noraise {
    _ => fail("expected non-string entry to fail")
  }
  try
    @cli.parse_contract(
      "entry = \"main\"\n\n[[assets]]\nbundlePath = \"assets/a\"",
    )
  catch {
    @cli.Fail(message) =>
      inspect(
        message,
        content="passport.toml: asset is missing required string field \"source\"",
      )
    _ => fail("expected a CliError failure")
  } noraise {
    _ => fail("expected incomplete asset to fail")
  }
  try
    @cli.parse_contract(
      "entry = \"main\"\n[[assets]]\nsource = \"a\"\nbundlePath = \"b\"\npcmLoop = true",
    )
  catch {
    @cli.Fail(message) =>
      inspect(
        message,
        content="passport.toml: asset field \"pcmLoop\" is not supported",
      )
    _ => fail("expected a CliError failure")
  } noraise {
    _ => fail("expected legacy pcmLoop to fail")
  }
}

///|
test "parse_contract accepts a device entry with the same path rules as entry" {
  let contract = @cli.parse_contract(
    "entry = \"runtime_wasm\"\ndeviceEntry = \"runtime_native\"",
  )
  debug_inspect(contract.device_entry, content="Some(\"runtime_native\")")
  try
    @cli.parse_contract("entry = \"main\"\ndeviceEntry = \"../escape\"")
  catch {
    @cli.Fail(_) => ()
    _ => fail("expected an unsafe deviceEntry to fail")
  } noraise {
    _ => fail("expected an unsafe deviceEntry to fail")
  }
  try @cli.parse_contract("entry = \"main\"\ndeviceEntry = 7") catch {
    @cli.Fail(message) =>
      inspect(
        message,
        content="passport.toml: \"deviceEntry\" must be a string",
      )
    _ => fail("expected a CliError failure")
  } noraise {
    _ => fail("expected a non-string deviceEntry to fail")
  }
}

///|
test "parse_contract reads hostDependencies as host-id to path entries" {
  let contract = @cli.parse_contract(
    "entry = \"main\"\n\n[hostDependencies.\"folotoy-ai-passport\"]\npath = \"external/folotoy-ai-passport\"",
  )
  debug_inspect(
    @cli.host_dependency_path(contract, "folotoy-ai-passport"),
    content="Some(\"external/folotoy-ai-passport\")",
  )
  debug_inspect(@cli.host_dependency_path(contract, "web"), content="None")
  try
    @cli.parse_contract(
      "entry = \"main\"\n\n[hostDependencies.\"folotoy-ai-passport\"]\npath = \"../escape\"",
    )
  catch {
    @cli.Fail(message) =>
      inspect(
        message,
        content="passport.toml: hostDependencies[\"folotoy-ai-passport\"].\"path\" contains an unsafe path component",
      )
    _ => fail("expected an unsafe hostDependency path to fail")
  } noraise {
    _ => fail("expected an unsafe hostDependency path to fail")
  }
  try
    @cli.parse_contract(
      "entry = \"main\"\n\n[hostDependencies.\"folotoy-ai-passport\"]",
    )
  catch {
    @cli.Fail(message) =>
      inspect(
        message,
        content="passport.toml: hostDependencies[\"folotoy-ai-passport\"] is missing required string field \"path\"",
      )
    _ => fail("expected a hostDependency without path to fail")
  } noraise {
    _ => fail("expected a hostDependency without path to fail")
  }
}

///|
test "entry_url_path is independent of assets and sounds" {
  inspect(
    @cli.entry_url_path(@cli.parse_contract("entry = \"main\"")),
    content="index.html",
  )
  inspect(
    @cli.entry_url_path(
      @cli.parse_contract(
        "entry = \"main\"\n\n[[assets]]\nsource = \"map.bin\"\nbundlePath = \"assets/map.bin\"\n\n[[sounds]]\nname = \"jump\"\nsource = \"assets/jump.pcm\"",
      ),
    ),
    content="index.html",
  )
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
  inspect(text.contains("shared APSB sound-bank playback"), content="true")
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
test "moon_mod_scalar reads strict quoted module facts" {
  let text = "name=\"colmugx/ai-passport\" // module id\n\nversion = \"0.0.4\"\n\nsource   =   \"src\" // package root\n"
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
  debug_inspect(
    @cli.moon_mod_scalar(
      "name = \"https://example.invalid/app\" // comment", "name",
    ),
    content="Some(\"https://example.invalid/app\")",
  )
}

///|
test "moon_mod_scalar rejects duplicate and malformed target fields" {
  for
    text in [
      "name = \"a/b\"\nname = \"c/d\"\n", "name = colmugx/app\n", "name = \"unterminated\n",
      "name = \"a/b\" trailing\n",
    ] {
    try @cli.moon_mod_scalar(text, "name") catch {
      @cli.Fail(_) => ()
      _ => fail("expected a CliError failure")
    } noraise {
      _ => fail("expected malformed moon.mod metadata to fail")
    }
  }
}

///|
test "entry executable detection ignores comments and unrelated strings" {
  inspect(
    @cli.entry_is_executable_package("pkgtype(kind: \"executable\")"),
    content="true",
  )
  inspect(
    @cli.entry_is_executable_package("pkgtype(\n  kind: \"executable\",\n)\n"),
    content="true",
  )
  inspect(
    @cli.entry_is_executable_package("options(\n  \"is-main\": true,\n)\n"),
    content="true",
  )
  inspect(
    @cli.entry_is_executable_package(
      "// pkgtype(kind: \"executable\")\npkgtype(kind: \"foreign_library\")",
    ),
    content="false",
  )
  inspect(
    @cli.entry_is_executable_package(
      "description = \"pkgtype(kind: executable)\"\n",
    ),
    content="false",
  )
  inspect(
    @cli.entry_is_executable_package("pkgtype(other_kind: \"executable\")\n"),
    content="false",
  )
  inspect(
    @cli.entry_is_executable_package(
      "options(\n  \"is-main\": false,\n  \"native-stub\": true,\n)\n",
    ),
    content="false",
  )
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
      sounds: [],
      host_dependencies: [],
    },
  }
  inspect(
    @cli.expected_wasm_artifact(project, project.contract.entry),
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
      sounds: [],
      host_dependencies: [],
    },
  }
  inspect(
    @cli.expected_wasm_artifact(nested, nested.contract.entry),
    content="/work/app/_build/wasm/release/build/cmd/greeter/greeter.wasm",
  )
}

///|
test "generated entries live under the module source root" {
  let src_rooted : @cli.Project = {
    root: "/work/app",
    module_name: "colmugx/app",
    source_dir: "src",
    contract: {
      entry: "app",
      device_entry: None,
      assets: [],
      sounds: [],
      host_dependencies: [],
    },
  }
  // Filesystem paths carry the source root; package paths never do, and
  // moon's _build layout uses the package path form.
  inspect(
    @cli.generated_web_entry_dir(src_rooted),
    content="/work/app/src/passport-generated/web",
  )
  inspect(
    @cli.generated_device_entry_dir(src_rooted),
    content="/work/app/src/passport-generated/folotoy-ai-passport",
  )
  inspect(@cli.generated_web_entry(), content="passport-generated/web")
  inspect(
    @cli.expected_wasm_artifact(src_rooted, @cli.generated_web_entry()),
    content="/work/app/_build/wasm/release/build/passport-generated/web/web.wasm",
  )
  inspect(
    @cli.application_package_import(src_rooted),
    content="colmugx/app/app",
  )
  let root_rooted : @cli.Project = { ..src_rooted, source_dir: "", }
  inspect(
    @cli.generated_web_entry_dir(root_rooted),
    content="/work/app/passport-generated/web",
  )
  inspect(
    @cli.expected_wasm_artifact(root_rooted, @cli.generated_web_entry()),
    content="/work/app/_build/wasm/release/build/passport-generated/web/web.wasm",
  )
}
