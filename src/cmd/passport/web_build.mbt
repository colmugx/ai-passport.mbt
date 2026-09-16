///|
/// Resolution of the SDK's own Web Host files (index.html,
/// passport-host.js, pcm-worklet.js) for a downstream project. The files
/// always come from the SDK release the project actually installed — never
/// from GitHub and never from MoonBit's private dependency-cache layout.

///|
const SDK_MODULE : String = "colmugx/ai-passport"

///|
const SDK_HOST_DIR : String = "hosts/web"

///|
async fn package_has_host_files(package_dir : String) -> Bool {
  for file in @cli.sdk_host_files() {
    if !@fs.exists("\{package_dir}/\{SDK_HOST_DIR}/\{file}") {
      return false
    }
  }
  true
}

///|
/// Locates the installed SDK package directory for a project. A downstream
/// project must have materialized its declared dependencies with `moon
/// install`; the CLI deliberately does not depend on Moon's internal cache
/// directory structure.
async fn resolve_sdk_package_dir(project : @cli.Project) -> String {
  // The SDK module building itself uses the checkout's co-versioned host.
  if project.module_name == SDK_MODULE && package_has_host_files(project.root) {
    return "\{project.root}/\{SDK_HOST_DIR}"
  }
  // Downstream projects use the dependency installation selected by Moon.
  let module_local = "\{project.root}/.mooncakes/\{SDK_MODULE}"
  if package_has_host_files(module_local) {
    return "\{module_local}/\{SDK_HOST_DIR}"
  }
  @cli.fail_cli(
    "the \{SDK_MODULE} dependency is not installed for this project; run 'moon install' in the project and retry",
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
/// Locates the built application wasm: the conventional artifact first, then
/// exactly one `.wasm` file in the entry's build directory.
async fn locate_wasm_artifact(project : @cli.Project) -> String {
  let conventional = @cli.expected_wasm_artifact(project)
  if @fs.exists(conventional) {
    return conventional
  }
  let entry_build_dir = @cli.under_root(
    project.root,
    "_build/wasm/release/build/\{project.contract.entry}",
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
    "no built application wasm for entry \"\{project.contract.entry}\" (expected \{conventional})",
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
/// `passport build --host <id>`: compile the application entry and assemble
/// the generic Web Host bundle.
async fn build_command(sub : @argparse.Matches) -> Unit {
  let host_id = option_value(sub, "host", "web")
  let _ = @cli.require_implemented_host(host_id)
  let project = load_project(option_value(sub, "project", "."))

  // Compile only the declared entry package instead of rebuilding every
  // package in a potentially large application module.
  let entry_dir = @cli.entry_package_dir(project)
  run_step(
    @shell.Cmd::Cmd(
      "moon",
      ["build", entry_dir, "--target", "wasm", "--release"],
      cwd=project.root,
    ),
    "building application entry \"\{project.contract.entry}\" (wasm release)",
  )
  let wasm_artifact = locate_wasm_artifact(project)
  let sdk_dir = resolve_sdk_package_dir(project)

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
