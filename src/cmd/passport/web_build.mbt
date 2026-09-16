///|
/// Resolution of the SDK's own Web Host files (index.html,
/// passport-host.js, pcm-worklet.js) for a downstream project. The files
/// always come from the SDK release the project actually builds against —
/// never from a git checkout, never from GitHub:
///
/// 1. building the SDK module itself: the checkout's own `hosts/web/`
///    (co-versioned with the CLI under development);
/// 2. the project's module-local mooncakes install (`.mooncakes/`), which is
///    exactly what `moon build` resolved the SDK dependency from;
/// 3. the versioned user dependency cache, pinned by the project's
///    moon.mod import when there is one.

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
/// Locates the installed SDK package directory for a project. `mod_text` is
/// the project's moon.mod text (used to pin the cache version).
async fn resolve_sdk_package_dir(
  project : @cli.Project,
  mod_text : String,
) -> String {
  // 1. The SDK module building itself.
  if project.module_name == SDK_MODULE && package_has_host_files(project.root) {
    return "\{project.root}/\{SDK_HOST_DIR}"
  }
  // 2. Module-local mooncakes resolution.
  let module_local = "\{project.root}/.mooncakes/\{SDK_MODULE}"
  if package_has_host_files(module_local) {
    return "\{module_local}/\{SDK_HOST_DIR}"
  }
  // 3. User dependency cache, versioned.
  guard @env.get_env_var("HOME") is Some(home) else {
    @cli.fail_cli(
      "cannot locate the \{SDK_MODULE} package (no HOME); run 'moon update' in the project and retry",
    )
  }
  let cache_root = "\{home}/.moon/cache/deps/v1/sources/\{SDK_MODULE}"
  if @fs.exists(cache_root) {
    match @cli.sdk_dependency_version(mod_text) {
      Some(version) => {
        let candidate = "\{cache_root}/\{version}"
        if package_has_host_files(candidate) {
          return "\{candidate}/\{SDK_HOST_DIR}"
        }
        @cli.fail_cli(
          "the pinned SDK dependency \{SDK_MODULE}@\{version} is not resolved yet (missing \{SDK_HOST_DIR} in the dependency cache); run 'moon update' in the project and retry",
        )
      }
      None => {
        let hits : Array[String] = []
        for version in @fs.readdir(cache_root) {
          if package_has_host_files("\{cache_root}/\{version}") {
            hits.push(version)
          }
        }
        if hits.length() == 1 {
          return "\{cache_root}/\{hits[0]}/\{SDK_HOST_DIR}"
        }
        if hits.length() > 1 {
          @cli.fail_cli(
            "ambiguous \{SDK_MODULE} dependency cache (\{hits.length()} versions ship \{SDK_HOST_DIR}); pin the dependency version in moon.mod and retry",
          )
        }
      }
    }
  }
  @cli.fail_cli(
    "the published \{SDK_MODULE} package is not resolved for this project (no .mooncakes entry, no usable dependency cache); run 'moon update' in the project and retry",
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
    "no built application wasm for entry \"\{project.contract.entry}\" (expected \{conventional}); build with: moon build --target wasm --release",
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
/// `passport build --host <id>`: the complete generic Web build — resolve
/// the project, compile the application wasm against the resolved SDK,
/// assemble `.passport/web/` with the SDK Web Host files and the declared
/// assets.
async fn build_command(sub : @argparse.Matches) -> Unit {
  let host_id = option_value(sub, "host", "web")
  let descriptor = @cli.require_implemented_host(host_id)
  let _ = descriptor
  let project = load_project(option_value(sub, "project", "."))
  let mod_text = read_text_file("\{project.root}/moon.mod")
  // 1. Compile the application entry for the wasm target (release).
  run_step(
    @shell.Cmd::Cmd(
      "moon",
      ["build", "--target", "wasm", "--release"],
      cwd=project.root,
    ),
    "building the application (moon --target wasm, release)",
  )
  let wasm_artifact = locate_wasm_artifact(project)
  let sdk_dir = resolve_sdk_package_dir(project, mod_text)
  // 2. Assemble the bundle.
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
  // page from older tooling must never survive into a fresh bundle.
  let stale = "\{bundle}/app.html"
  if @fs.exists(stale) {
    @fs.remove(stale) catch {
      _ => @cli.fail_cli("cannot remove stale \{stale}")
    }
  }
  println("passport: bundle assembled at \{bundle}")
  println("passport: entry: /\{@cli.entry_url_path(project.contract)}")
}
