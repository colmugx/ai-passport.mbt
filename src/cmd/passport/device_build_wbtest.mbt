///|
/// Focused tests for the device capture's moon.pkg injection. The injection
/// mutates a downstream project's source for exactly one build invocation,
/// so its text handling is pinned here; the byte-exact restore around it is
/// enforced by the build flow itself.

///|
test "inject_capture_cc inserts into an options block" {
  let original = "supported_targets = \"native\"\n\npkgtype(kind: \"foreign_library\")\n\nimport {\n  \"colmugx/app/main\",\n}\n\noptions(\n  \"native-stub\": [ \"host_display_stub.c\" ],\n)\n"
  let injected = inject_capture_cc(
    original, "/work/app/.passport/x/cc", "src/runtime_native/moon.pkg",
  )
  inspect(
    injected.contains(
      "options(\n  link: { \"native\": { \"cc\": \"/work/app/.passport/x/cc\" } },\n  \"native-stub\"",
    ),
    content="true",
  )
  inspect(injected.contains("host_display_stub.c"), content="true")
}

///|
test "inject_capture_cc appends an options block when absent" {
  let original = "supported_targets = \"native\"\n\npkgtype(kind: \"foreign_library\")\n"
  let injected = inject_capture_cc(original, "/w/cc", "pkg/moon.pkg")
  inspect(
    injected.contains(
      "\noptions(\n  link: { \"native\": { \"cc\": \"/w/cc\" } },\n)\n",
    ),
    content="true",
  )
}

///|
test "inject_capture_cc handles the legacy JSON object format" {
  let original = "{\n  \"import\": [\n    \"colmugx/app/main\"\n  ],\n  \"native-stub\": [\n    \"stub.c\"\n  ]\n}\n"
  let injected = inject_capture_cc(original, "/w/cc", "pkg/moon.pkg")
  inspect(
    injected.contains(
      "{\n  \"link\": { \"native\": { \"cc\": \"/w/cc\" } },\n  \"import\"",
    ),
    content="true",
  )
}

///|
test "inject_capture_cc refuses an existing link override" {
  let original = "options(\n  link: { \"native\": { \"cc\": \"/elsewhere/cc\" } },\n)\n"
  try inject_capture_cc(original, "/w/cc", "pkg/moon.pkg") catch {
    @cli.Fail(message) =>
      inspect(
        message.contains("already declares a link override"),
        content="true",
      )
    _ => fail("expected a CliError failure")
  } noraise {
    _ => fail("expected an existing link override to fail")
  }
}

///|
test "plan_bsp_resolution prefers a present project-provided checkout" {
  debug_inspect(
    plan_bsp_resolution(
      Some("/work/tpl/external/folotoy-ai-passport"),
      true,
      "/work/tpl/.passport/deps/folotoy-ai-passport/x",
      true,
    ),
    content="ProjectProvided(\"/work/tpl/external/folotoy-ai-passport\")",
  )
}

///|
test "plan_bsp_resolution refuses a declared but missing checkout" {
  debug_inspect(
    plan_bsp_resolution(
      Some("/work/tpl/external/folotoy-ai-passport"),
      false,
      "/managed",
      false,
    ),
    content="DeclaredMissing(\"/work/tpl/external/folotoy-ai-passport\")",
  )
}

///|
test "plan_bsp_resolution reuses or materializes the managed clone" {
  debug_inspect(
    plan_bsp_resolution(
      None,
      false,
      "/work/tpl/.passport/deps/folotoy-ai-passport/rev",
      true,
    ),
    content="ManagedReady(\"/work/tpl/.passport/deps/folotoy-ai-passport/rev\")",
  )
  debug_inspect(
    plan_bsp_resolution(
      None,
      false,
      "/work/tpl/.passport/deps/folotoy-ai-passport/rev",
      false,
    ),
    content="MaterializeManaged(\"/work/tpl/.passport/deps/folotoy-ai-passport/rev\")",
  )
}

///|
test "managed_bsp_dir is per revision, never a moving ref" {
  let project : @cli.Project = {
    root: "/work/tpl",
    module_name: "colmugx/app",
    source_dir: "src",
    contract: {
      entry: "runtime_wasm",
      device_entry: None,
      assets: [],
      sounds: [],
      host_dependencies: [],
    },
  }
  let dir = managed_bsp_dir(project)
  inspect(dir.contains(BSP_COMMIT), content="true")
  inspect(
    dir.has_prefix("/work/tpl/.passport/deps/folotoy-ai-passport/"),
    content="true",
  )
}

///|
test "device workspace preserves only incremental ESP-IDF state" {
  for name in ["build", "managed_components", "sdkconfig", "sdkconfig.old"] {
    inspect(device_workspace_preserve(name), content="true")
  }
  for
    name in [
      "components", "main", "tools", "dependencies.lock", "toolchain", "legacy.c",
    ] {
    inspect(device_workspace_preserve(name), content="false")
  }
}
