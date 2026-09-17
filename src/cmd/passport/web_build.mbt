///|
/// Resolution of the SDK's own Web Host files (index.html,
/// passport-host.js, pcm-worklet.js) for a downstream project. The files
/// always come from the SDK release Moon materialized for the project — never
/// from GitHub and never from MoonBit's private dependency-cache layout.

///|
const SDK_MODULE : String = "colmugx/ai-passport"

///|
const SDK_HOST_DIR : String = "hosts/web"

///|
const HOST_DIR_FOLOTOY : String = "hosts/folotoy/ai-passport"

///|
async fn package_has_host_files(
  module_dir : String,
  host_dir : String,
  files : Array[String],
) -> Bool {
  for file in files {
    if !@fs.exists("\{module_dir}/\{host_dir}/\{file}") {
      return false
    }
  }
  true
}

///|
/// Locates the SDK source tree selected for a project. Build/doctor first run
/// a normal Moon project operation (`moon build` / `moon check`), allowing
/// Moon itself to resolve and materialize declared dependencies. The CLI then
/// consumes the resulting module-local `.mooncakes` tree instead of depending
/// on any undocumented global cache layout.
async fn resolve_sdk_host_dir(
  project : @cli.Project,
  host_dir : String,
  files : Array[String],
) -> String {
  // The SDK module building itself uses the checkout's co-versioned host.
  if project.module_name == SDK_MODULE &&
    package_has_host_files(project.root, host_dir, files) {
    return "\{project.root}/\{host_dir}"
  }
  // Downstream projects use the dependency materialized by Moon.
  let module_local = "\{project.root}/.mooncakes/\{SDK_MODULE}"
  if package_has_host_files(module_local, host_dir, files) {
    return "\{module_local}/\{host_dir}"
  }
  @cli.fail_cli(
    "Moon did not materialize \{SDK_MODULE} for this project; verify moon.mod and run a normal moon check/build before retrying",
  )
}

///|
/// Runs one external step, streaming its output lines; a non-zero exit fails
/// the command with context.
async fn run_step(cmd : @shell.Cmd, what : String) -> Unit {
  println("passport: \{what}")
  let code = cmd.each_line(line => println("  \{line}"))
  if code != 0 {
    @cli.fail_cli("\{what} failed with exit code \{code}")
  }
}

///|
/// Locates the built application wasm for one built entry package path:
/// the conventional artifact first, then exactly one `.wasm` file in the
/// entry's build directory.
async fn locate_wasm_artifact(project : @cli.Project, entry : String) -> String {
  let conventional = @cli.expected_wasm_artifact(project, entry)
  if @fs.exists(conventional) {
    return conventional
  }
  let entry_build_dir = @cli.under_root(
    project.root,
    "_build/wasm/release/build/\{entry}",
  )
  if @fs.exists(entry_build_dir) {
    let wasm_files = @fs.readdir(entry_build_dir).filter(fn(name) {
      name.has_suffix(".wasm")
    })
    if wasm_files.length() == 1 {
      return "\{entry_build_dir}/\{wasm_files[0]}"
    }
  }
  @cli.fail_cli(
    "no built application wasm for entry \"\{entry}\" (expected \{conventional})",
  )
}

///|
/// Copies one file, creating the destination's parent directories.
async fn copy_file(from : String, to : String) -> Unit {
  let data = @fs.read_file(from) catch {
    _ => @cli.fail_cli("cannot read \{from}")
  }
  @fs.write_file(to, data) catch {
    _ => @cli.fail_cli("cannot write \{to}")
  }
}

///|
/// `passport build --host <id>`: route to the Host's build backend. Unknown
/// hosts fail inside the backend entry (no silent web fallback).
async fn build_command(sub : @argparse.Matches) -> Unit {
  let host_id = option_value(sub, "host", "web")
  match host_id {
    "folotoy-ai-passport" => device_build_command(sub)
    _ => web_bundle_build(sub)
  }
}

///|
/// The Web Host build backend: compile the application entry and assemble
/// the generic bundle.
async fn web_bundle_build(sub : @argparse.Matches) -> Unit {
  let host_id = option_value(sub, "host", "web")
  let _ = @cli.require_implemented_host(host_id)
  let project = load_project(option_value(sub, "project", "."))

  // Compile only the entry package instead of rebuilding every package in a
  // potentially large application module. An executable entry is the legacy
  // (published 0.0.5) contract and builds directly; a library entry is the
  // application contract and builds through the generated Web adapter.
  let entry_moon_pkg = "\{@cli.entry_package_dir(project)}/moon.pkg"
  guard @fs.exists(entry_moon_pkg) else {
    @cli.fail_cli(
      "entry package \"\{project.contract.entry}\" has no moon.pkg (\{entry_moon_pkg})",
    )
  }
  let legacy_entry = @cli.entry_is_executable_package(
    read_text_file(entry_moon_pkg),
  )
  let build_target : String = if legacy_entry {
    @cli.entry_package_dir(project)
  } else {
    generate_web_entry(project)
  }
  let artifact_entry : String = if legacy_entry {
    project.contract.entry
  } else {
    @cli.generated_web_entry()
  }
  run_step(
    @shell.Cmd::Cmd(
      "moon",
      ["build", build_target, "--target", "wasm", "--release"],
      cwd=project.root,
    ),
    "building application entry \"\{project.contract.entry}\" (wasm release)",
  )
  let wasm_artifact = locate_wasm_artifact(project, artifact_entry)
  let sdk_dir = resolve_sdk_host_dir(
    project,
    SDK_HOST_DIR,
    @cli.sdk_host_files(),
  )

  let bundle = @cli.under_root(project.root, @cli.BUNDLE_DIR)
  let bundle_assets = "\{bundle}/assets"
  if !@fs.exists(bundle_assets) {
    @fs.mkdir(bundle_assets, recursive=true) catch {
      _ => @cli.fail_cli("cannot create \{bundle_assets}")
    }
  }
  copy_file(wasm_artifact, "\{bundle}/app.wasm")
  for file in @cli.sdk_host_files() {
    copy_file("\{sdk_dir}/\{file}", "\{bundle}/\{file}")
  }
  for asset in project.contract.assets {
    let source = @cli.under_root(project.root, asset.source)
    guard @fs.exists(source) else {
      @cli.fail_cli("contract asset source is missing: \{asset.source}")
    }
    let destination = "\{bundle}/\{asset.bundle_path}"
    match destination.rev_find("/") {
      Some(at) => {
        let dir = destination[:at].to_owned()
        if !@fs.exists(dir) {
          @fs.mkdir(dir, recursive=true) catch {
            _ => @cli.fail_cli("cannot create \{dir}")
          }
        }
      }
      None => ()
    }
    copy_file(source, destination)
  }
  // The SDK index.html is the only web entry; a stale generated bootstrap
  // page from older tooling must never survive into the supported bundle.
  let stale = "\{bundle}/app.html"
  if @fs.exists(stale) {
    @fs.remove(stale) catch {
      _ => @cli.fail_cli("cannot remove stale \{stale}")
    }
  }
  println("passport: bundle assembled at \{bundle}")
  println("passport: entry: /\{@cli.entry_url_path(project.contract)}")
}
