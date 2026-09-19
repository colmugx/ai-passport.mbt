///|
/// The physical Host build backend for `folotoy-ai-passport`: capture the
/// project device entry's native C, then build the ESP-IDF firmware inside a
/// materialized workspace under the project root. The project's source tree
/// is never modified by this flow (the temporary capture injection is
/// restored byte-exact before the command reports anything).

///|
/// The toolchain versions pinned by the physical Host implementation.
const MOON_VERSION_PIN : String = "moon 0.1.20260915 (2e1a46d 2026-09-15)"

///|
const IDF_VERSION_PIN : String = "ESP-IDF v5.5.3"

///|
/// Name of the capture cc inside the toolchain dir and of the firmware's
/// music asset; the host components read these exact names.
const CAPTURE_CC_NAME : String = "cc"

///|
/// The capture cc lives in this directory at the workspace root: moon
/// derives the native archiver from the link cc's directory, so the dir
/// also holds the symlinked real system archiver. The host CMakeLists never
/// reference it.
const CAPTURE_TOOLCHAIN_DIR : String = "toolchain"

///|
const CAPTURE_AR_NAME : String = "ar"

///|
const MUSIC_ASSET_NAME : String = "passport_music.pcm"

///|
const APP_PARTITION_SIZE : Int64 = 0x380000L

///|
/// Verifies every file of a sha256sum-format manifest relative to the
/// process cwd. Shelled out so the CLI gains no new dependency; python3 is
/// already a doctor dependency.
const RUNTIME_SHA256_SCRIPT : String =
  #|import hashlib, sys
  #|bad = 0
  #|for line in open(sys.argv[1]):
  #|    line = line.strip()
  #|    if not line:
  #|        continue
  #|    digest, path = line.split(None, 1)
  #|    try:
  #|        got = hashlib.sha256(open(path, 'rb').read()).hexdigest()
  #|    except OSError:
  #|        print('missing ' + path)
  #|        bad = 1
  #|        continue
  #|    if got != digest:
  #|        print('mismatch ' + path)
  #|        bad = 1
  #|sys.exit(bad)

///|
/// Runs one command to completion; a spawn failure (tool not installed)
/// becomes None instead of an error so callers can report it as a failed
/// check.
async fn try_output(cmd : @shell.Cmd) -> @shell.Output? {
  Some(cmd.output()) catch {
    _ => None
  }
}

///|
fn first_line(text : String) -> String {
  match text.find("\n") {
    Some(at) => text[:at].to_owned()
    None => text
  }
}

///|
/// Resolves the real system archiver from PATH. moon derives the native
/// archiver from the link cc's directory, so the capture build needs it
/// beside the capture cc; this check fails before any project mutation.
async fn system_archiver() -> String {
  let out = try_output(@shell.Cmd::Cmd("/bin/sh", ["-c", "command -v ar"]))
  let found = match out {
    Some(output) =>
      if output.exit_code() == 0 {
        output.stdout().trim().to_owned()
      } else {
        ""
      }
    None => ""
  }
  guard found != "" else {
    @cli.fail_cli(
      "the system archiver 'ar' is not on PATH; the device build symlinks it beside the capture cc (moon derives the archiver from the link cc's directory)",
    )
  }
  found
}

///|
fn moon_home_dir() -> String raise {
  match @env.get_env_var("MOON_HOME") {
    Some(dir) => dir
    None =>
      match @env.get_env_var("HOME") {
        Some(home) => "\{home}/.moon"
        None =>
          @cli.fail_cli(
            "neither MOON_HOME nor HOME is set; the pinned MoonBit runtime location is unknown",
          )
      }
  }
}

///|
/// Returns None when every manifest entry hashes correctly under MOON_HOME,
/// else the human-readable problem detail.
async fn verify_runtime_sha256(manifest : String) -> String? {
  verify_sha256_manifest(manifest, moon_home_dir())
}

///|
/// Returns None when every sha256sum-format manifest entry hashes correctly
/// relative to `root`, else the human-readable problem detail.
async fn verify_sha256_manifest(manifest : String, root : String) -> String? {
  let out = try_output(
    @shell.Cmd::Cmd(
      "python3",
      ["-c", RUNTIME_SHA256_SCRIPT, manifest],
      cwd=root,
    ),
  )
  match out {
    None => Some("python3 is unavailable")
    Some(output) =>
      if output.exit_code() == 0 {
        None
      } else {
        let detail = output.stdout().trim().to_owned()
        if detail == "" {
          Some("the runtime manifest check failed without output")
        } else {
          Some(detail)
        }
      }
  }
}

///|
/// The only FoloToy upstream revision this Host release is tested against.
/// Managed clones check out exactly this commit; the content manifest
/// (`bsp.sha256`) remains the build-time authority either way.
const BSP_COMMIT : String = "c21a015d44f2bcc02b4d859532d74cd7aefe69be"

///|
const BSP_REPO_URL : String = "https://github.com/FoloToy/ai-passport.git"

///|
/// CLI-managed external Host dependencies live under the project's ignored
/// .passport tree, per host and revision: a revision change never rewrites
/// a checkout another build may still be reading.
fn managed_bsp_dir(project : @cli.Project) -> String {
  @cli.under_root(
    project.root,
    ".passport/deps/folotoy-ai-passport/\{BSP_COMMIT}",
  )
}

///|
/// How a Host build obtains its external dependency. A contract-declared
/// path is authoritative: a missing or drifted one is a project error to
/// surface, never something the CLI silently replaces with a download.
enum BspPlan {
  ProjectProvided(String)
  ManagedReady(String)
  MaterializeManaged(String)
  DeclaredMissing(String)
} derive(Eq, Debug)

///|
fn plan_bsp_resolution(
  declared : String?,
  provided_exists : Bool,
  managed_dir : String,
  managed_ready : Bool,
) -> BspPlan {
  match declared {
    Some(path) =>
      if provided_exists {
        ProjectProvided(path)
      } else {
        DeclaredMissing(path)
      }
    None =>
      if managed_ready {
        ManagedReady(managed_dir)
      } else {
        MaterializeManaged(managed_dir)
      }
  }
}

///|
/// HEAD of `dir` when it is a git checkout, else None.
async fn git_head(dir : String) -> String? {
  match try_output(@shell.Cmd::Cmd("git", ["-C", dir, "rev-parse", "HEAD"])) {
    Some(out) =>
      if out.exit_code() == 0 && out.stdout() != "" {
        Some(first_line(out.stdout()).trim().to_owned())
      } else {
        None
      }
    None => None
  }
}

///|
/// Resolves the FoloToy checkout for a device build: the contract's
/// `hostDependencies` path when declared (the reference template's pinned
/// submodule), else the managed clone — cloned or re-pinned only when
/// missing or on the wrong revision. Returns the checkout and whether the
/// project provided it, for provenance logging.
async fn ensure_bsp_checkout(project : @cli.Project) -> (String, Bool) {
  let declared = match
    @cli.host_dependency_path(project.contract, "folotoy-ai-passport") {
    Some(rel) => Some(@cli.under_root(project.root, rel))
    None => None
  }
  let managed_dir = managed_bsp_dir(project)
  match
    plan_bsp_resolution(
      declared,
      match declared {
        Some(path) => @fs.exists("\{path}/components/bsp/include")
        None => false
      },
      managed_dir,
      @fs.exists("\{managed_dir}/components/bsp/include"),
    ) {
    ProjectProvided(path) => (path, true)
    DeclaredMissing(path) =>
      @cli.fail_cli(
        "passport.toml declares hostDependencies[\"folotoy-ai-passport\"] but no checkout exists at \{path}; fix the path, or remove the field to let the CLI manage the dependency",
      )
    ManagedReady(dir) => {
      if git_head(dir) != Some(BSP_COMMIT) {
        run_step(
          @shell.Cmd::Cmd("git", ["-C", dir, "fetch", "--quiet", "origin"]),
          "re-pinning the managed FoloToy checkout",
        )
        run_step(
          @shell.Cmd::Cmd("git", ["-C", dir, "checkout", "--quiet", BSP_COMMIT]),
          "checking out the pinned FoloToy revision",
        )
      }
      (dir, false)
    }
    MaterializeManaged(dir) => {
      // A partial or corrupt managed clone restarts clean.
      if @fs.exists(dir) {
        @fs.rmdir(dir, recursive=true) catch {
          _ =>
            @cli.fail_cli("cannot clear the stale managed checkout at \{dir}")
        }
      }
      ensure_dir("\{project.root}/.passport/deps/folotoy-ai-passport")
      run_step(
        @shell.Cmd::Cmd("git", ["clone", "--quiet", BSP_REPO_URL, dir]),
        "cloning the pinned FoloToy dependency",
      )
      run_step(
        @shell.Cmd::Cmd("git", ["-C", dir, "checkout", "--quiet", BSP_COMMIT]),
        "checking out the pinned FoloToy revision",
      )
      (dir, false)
    }
  }
}

///|
/// Verifies the resolved checkout against the tracked content manifest and
/// connects it to the generated ESP-IDF project: the folotoy_bsp component
/// compiles the upstream sources in place through the generated one-line
/// cmake include. Third-party source never enters the SDK release or the
/// build workspace as files.
async fn connect_bsp(
  project : @cli.Project,
  sdk_host : String,
  workspace : String,
) -> Unit {
  let (repo, project_provided) = ensure_bsp_checkout(project)
  let revision = match git_head(repo) {
    Some(rev) => rev
    None => "unknown-commit (content-verified)"
  }
  let origin = if project_provided { "project-provided" } else { "CLI-managed" }
  println(
    "passport: folotoy-ai-passport dependency: \{repo} @ \{revision} (\{origin})",
  )
  let manifest = "\{sdk_host}/components/folotoy_bsp/bsp.sha256"
  guard @fs.exists(manifest) else {
    @cli.fail_cli("the SDK device Host has no BSP manifest: \{manifest}")
  }
  match verify_sha256_manifest(manifest, "\{repo}/components/bsp") {
    Some(problem) =>
      @cli.fail_cli(
        "the FoloToy checkout at \{repo} does not match the pinned manifest: \{problem}",
      )
    None => ()
  }
  @fs.write_file(
    "\{workspace}/components/folotoy_bsp/upstream.cmake",
    @utf8.encode("set(FOTOLOY_BSP_ROOT \"\{repo}/components/bsp\")\n"),
  ) catch {
    _ =>
      @cli.fail_cli(
        "cannot write \{workspace}/components/folotoy_bsp/upstream.cmake",
      )
  }
}

///|
fn pcm_loop_asset(project : @cli.Project) -> @cli.AssetEntry? {
  let mut found : @cli.AssetEntry? = None
  for asset in project.contract.assets {
    if asset.pcm_loop {
      found = Some(asset)
    }
  }
  found
}

///|
/// The application music decision for a device build. A project declares at
/// most one looping PCM asset (the contract rejects more); declaring none is
/// a valid no-audio application, so firmware builds without a music blob and
/// the Host reports playback unavailable.
enum DeviceMusicPlan {
  Music(@cli.AssetEntry)
  NoMusic
} derive(Eq, Debug)

///|
fn plan_device_music(project : @cli.Project) -> DeviceMusicPlan {
  match pcm_loop_asset(project) {
    Some(asset) => Music(asset)
    None => NoMusic
  }
}

///|
/// Host material never copied into a device workspace: the Host's own test
/// tree and README are SDK development material.
fn device_workspace_skip(name : String) -> Bool {
  name == "test" || name == "README.md"
}

///|
/// Expensive ESP-IDF state that survives Host source refreshes. Everything
/// else at the workspace root is CLI-owned Host/source/generated material and
/// is rebuilt from the current SDK on every device build.
fn device_workspace_preserve(name : String) -> Bool {
  name == "build" ||
  name == "managed_components" ||
  name == "sdkconfig" ||
  name == "sdkconfig.old"
}

///|
/// Creates `path` with parents, tolerating an existing directory.
async fn ensure_dir(path : String) -> Unit {
  @fs.mkdir(path, recursive=true) catch {
    _ =>
      if !(@fs.kind(path) is Directory) {
        @cli.fail_cli("cannot create \{path}")
      }
  }
}

///|
/// Removes stale Host/source/generated workspace entries while preserving the
/// expensive ESP-IDF incremental state. Every candidate is canonicalized
/// immediately before deletion so a symlink cannot redirect recursive cleanup
/// outside the device workspace.
async fn prune_device_workspace(
  project : @cli.Project,
  workspace : String,
) -> Unit {
  let workspace_root = @fs.realpath(workspace) catch {
    _ => @cli.fail_cli("cannot resolve device workspace at \{workspace}")
  }
  guard
    workspace_root != project.root &&
    path_is_within(project.root, workspace_root)
  else {
    @cli.fail_cli(
      "refusing to prune device workspace outside the project root",
    )
  }
  for name in @fs.readdir(workspace) {
    let target = "\{workspace}/\{name}"
    let resolved = @fs.realpath(target) catch {
      _ =>
        @cli.fail_cli(
          "cannot resolve device workspace entry before cleanup: \{target}",
        )
    }
    guard
      resolved != workspace_root &&
      path_is_within(workspace_root, resolved)
    else {
      @cli.fail_cli(
        "refusing to prune device workspace entry outside \{workspace}",
      )
    }
    if device_workspace_preserve(name) {
      continue
    }
    if @fs.kind(target) is Directory {
      @fs.rmdir(target, recursive=true) catch {
        _ => @cli.fail_cli("cannot clear stale device workspace entry at \{target}")
      }
    } else {
      @fs.remove(target) catch {
        _ => @cli.fail_cli("cannot remove stale device workspace entry at \{target}")
      }
    }
  }
}

///|
/// Copies one current SDK Host subtree into the refreshed workspace. ESP-IDF
/// caches are preserved separately by `prune_device_workspace`; this copy
/// therefore never needs to preserve old Host source files.
async fn copy_tree(from : String, to : String) -> Unit {
  if @fs.kind(from) is Directory {
    ensure_dir(to)
    for name in @fs.readdir(from) {
      copy_tree("\{from}/\{name}", "\{to}/\{name}")
    }
  } else {
    copy_file(from, to)
    if from.has_suffix(".sh") {
      @fs.chmod(to, 0o755) catch {
        _ => ()
      }
    }
  }
}

///|
/// Injects the temporary capture cc into the device entry's moon.pkg text.
/// Handles the current MoonBit package format (`options(...)` blocks) and
/// the legacy JSON object format. Fails when the project already declares a
/// link override: the capture must own this invocation only.
fn inject_capture_cc(
  text : String,
  cc_path : String,
  pkg_path : String,
) -> String raise {
  guard !(text.contains("link:") || text.contains("\"link\"")) else {
    @cli.fail_cli(
      "\{pkg_path} already declares a link override; remove it before a device build",
    )
  }
  let link_value = "\"native\": { \"cc\": \"\{cc_path}\" }"
  match text.find("options(") {
    Some(at) => {
      let head = text[:at + "options(".length()].to_owned()
      let tail = text[at + "options(".length():].to_owned()
      "\{head}\n  link: { \{link_value} },\{tail}"
    }
    None =>
      if text.trim().has_prefix("{") {
        match text.find("{") {
          Some(at) => {
            let head = text[:at + 1].to_owned()
            let tail = text[at + 1:].to_owned()
            "\{head}\n  \"link\": { \{link_value} },\{tail}"
          }
          None =>
            @cli.fail_cli("cannot parse \{pkg_path} to inject the capture cc")
        }
      } else {
        "\{text}\noptions(\n  link: { \{link_value} },\n)\n"
      }
  }
}

///|
/// The native capture build of one device entry package. MOONBIT_NEW_NATIVE=0
/// keeps the proven legacy native pipeline that the capture cc and the
/// ESP-IDF runtime were validated against.
async fn run_capture_build(
  project : @cli.Project,
  entry_dir : String,
  capture_dir : String,
) -> Unit {
  run_step(
    @shell.Cmd::Cmd(
      "moon",
      ["build", entry_dir, "--target", "native", "--release"],
      cwd=project.root,
      env={ "MOON_CC_CAPTURE_DIR": capture_dir, "MOONBIT_NEW_NATIVE": "0" },
    ),
    "capturing the device entry C (native release)",
  )
}

///|
/// The capture is valid only when its manifest exists, lists at least one C
/// source, and every listed source was actually captured.
async fn validate_capture(capture_dir : String) -> Unit {
  let manifest = "\{capture_dir}/sources.txt"
  guard @fs.exists(manifest) else {
    @cli.fail_cli("the C capture produced no manifest: \{manifest}")
  }
  let text = read_text_file(manifest)
  let mut captured = 0
  for line in text.split("\n").to_array() {
    let name = line.trim()
    if name == "" {
      continue
    }
    guard @fs.exists("\{capture_dir}/\{name}") else {
      @cli.fail_cli("captured C source missing: \{name}")
    }
    captured = captured + 1
  }
  guard captured > 0 else {
    @cli.fail_cli("the C capture manifest lists no sources: \{manifest}")
  }
  println("passport: captured \{captured} C source(s) from the device entry")
}

///|
fn config_has_line(text : String, expected : String) -> Bool {
  for line in text.split("\n").to_array() {
    if line.trim() == expected {
      return true
    }
  }
  false
}

///|
/// The physical Host build flow, in order: contract device entry, SDK host
/// resolution, workspace materialization, the optional looping PCM asset,
/// native C capture, pinned toolchain verification, then the idf.py
/// reconfigure and build pair inside the workspace.
async fn device_build_command(sub : @argparse.Matches) -> Unit {
  let project = load_project(option_value(sub, "project", "."))
  // A declared `deviceEntry` is the legacy (published 0.0.5) contract: that
  // native package builds directly. Without one, a library application
  // entry gets the generated FoloToy adapter — and an executable entry
  // (the legacy wasm runtime) refuses before any host files are touched
  // (this refusal is the CI fixture gate).
  let legacy_device_entry = match project.contract.device_entry {
    Some(entry) => Some(entry)
    None => {
      let entry_moon_pkg = "\{@cli.entry_package_dir(project)}/moon.pkg"
      guard @fs.exists(entry_moon_pkg) else {
        @cli.fail_cli(
          "entry package \"\{project.contract.entry}\" has no moon.pkg (\{entry_moon_pkg})",
        )
      }
      if @cli.entry_is_executable_package(read_text_file(entry_moon_pkg)) {
        @cli.fail_cli(
          "host \"folotoy-ai-passport\" requires a \"deviceEntry\" package in passport.toml",
        )
      }
      None
    }
  }
  let sdk_host = resolve_sdk_host_dir(
    project,
    HOST_DIR_FOLOTOY,
    @cli.sdk_device_host_files(),
  )
  let workspace = @cli.under_root(project.root, @cli.DEVICE_BUNDLE_DIR)
  println("passport: materializing the device workspace from \{sdk_host}")
  ensure_dir(workspace)
  prune_device_workspace(project, workspace)
  for name in @fs.readdir(sdk_host) {
    if device_workspace_skip(name) {
      continue
    }
    copy_tree("\{sdk_host}/\{name}", "\{workspace}/\{name}")
  }
  let generated_dir = "\{workspace}/components/moonbit_device/generated"
  match plan_device_music(project) {
    Music(asset) => {
      let pcm_path = @cli.under_root(project.root, asset.source)
      guard @fs.exists(pcm_path) else {
        @cli.fail_cli("contract asset source is missing: \{asset.source}")
      }
      copy_file(pcm_path, "\{workspace}/\{MUSIC_ASSET_NAME}")
    }
    NoMusic => {
      // A no-audio application is valid: the firmware embeds no music and
      // the Host reports playback unavailable. A stale blob from an earlier
      // build of the same workspace must never survive into it.
      @fs.remove("\{workspace}/\{MUSIC_ASSET_NAME}") catch {
        _ => ()
      }
      println(
        "passport: no pcmLoop asset declared; firmware embeds no application music",
      )
    }
  }
  connect_bsp(project, sdk_host, workspace)
  let capture_dir = "\{generated_dir}/moonbit"
  let toolchain_dir = "\{workspace}/\{CAPTURE_TOOLCHAIN_DIR}"
  ensure_dir(toolchain_dir)
  let cc_path = "\{toolchain_dir}/\{CAPTURE_CC_NAME}"
  copy_file("\{sdk_host}/tools/moon_cc_capture.py", cc_path)
  @fs.chmod(cc_path, 0o755) catch {
    _ => @cli.fail_cli("cannot make \{cc_path} executable")
  }
  let system_ar = system_archiver()
  let ar_link = "\{toolchain_dir}/\{CAPTURE_AR_NAME}"
  // Re-point the link on every run (a stale link from an earlier build must
  // not pin an old archiver); removal of an absent link is fine.
  @fs.remove(ar_link) catch {
    _ => ()
  }
  @fs.symlink(target=system_ar, ar_link) catch {
    _ => @cli.fail_cli("cannot symlink \{system_ar} as \{ar_link}")
  }
  // A stale native build tree would skip compilation entirely and leave the
  // capture empty; the proven template flow resets it the same way.
  if @fs.exists("\{project.root}/_build/native") {
    @fs.rmdir("\{project.root}/_build/native", recursive=true) catch {
      _ =>
        @cli.fail_cli(
          "cannot clear \{project.root}/_build/native before the capture",
        )
    }
  }
  ensure_dir(capture_dir)
  match legacy_device_entry {
    Some(device_entry) => {
      let entry_dir = @cli.device_entry_package_dir(project, device_entry)
      let moon_pkg_path = "\{entry_dir}/moon.pkg"
      guard @fs.exists(moon_pkg_path) else {
        @cli.fail_cli(
          "device entry package \"\{device_entry}\" has no moon.pkg (\{moon_pkg_path})",
        )
      }
      // The injected capture cc is temporary state only: the saved bytes go
      // back no matter how the build ends, so the project source tree is
      // byte-identical after this command on success and failure alike.
      let moon_pkg_original = @fs.read_file(moon_pkg_path).binary()
      let injected = inject_capture_cc(
        read_text_file(moon_pkg_path),
        cc_path,
        moon_pkg_path,
      )
      @fs.write_file(moon_pkg_path, @utf8.encode(injected)) catch {
        _ => @cli.fail_cli("cannot write \{moon_pkg_path}")
      }
      let outcome : Result[Unit, Error] = try {
        run_capture_build(project, entry_dir, capture_dir)
        Ok(())
      } catch {
        err => Err(err)
      }
      @fs.write_file(moon_pkg_path, moon_pkg_original) catch {
        _ => @cli.fail_cli("cannot restore \{moon_pkg_path}")
      }
      match outcome {
        Err(err) => raise err
        Ok(_) => ()
      }
    }
    None => {
      // The generated adapter is CLI-owned, so its moon.pkg is written with
      // the capture cc already wired — nothing to inject or restore.
      let entry_dir = generate_device_entry(project, Some(cc_path))
      let outcome : Result[Unit, Error] = try {
        run_capture_build(project, entry_dir, capture_dir)
        Ok(())
      } catch {
        err => Err(err)
      }
      // The capture cc path is machine-specific build state; restore the
      // plain CLI-owned package so later moon commands stay valid.
      ignore(generate_device_entry(project, None))
      match outcome {
        Err(err) => raise err
        Ok(_) => ()
      }
    }
  }
  validate_capture(capture_dir)
  match try_output(@shell.Cmd::Cmd("idf.py", ["--version"])) {
    None =>
      @cli.fail_cli(
        "idf.py is unavailable; source the \{IDF_VERSION_PIN} export.sh before building",
      )
    Some(out) => {
      let first = first_line(out.stdout()).trim()
      guard first.contains(IDF_VERSION_PIN) else {
        @cli.fail_cli(
          "expected \{IDF_VERSION_PIN}; source the matching export.sh before building (got: \{first})",
        )
      }
    }
  }
  match try_output(@shell.Cmd::Cmd("moon", ["version"])) {
    None => @cli.fail_cli("the moon toolchain is unavailable")
    Some(out) => {
      let first = first_line(out.stdout()).trim()
      guard first == MOON_VERSION_PIN else {
        @cli.fail_cli(
          "expected \{MOON_VERSION_PIN}; the device build pins the MoonBit toolchain (got: \{first})",
        )
      }
    }
  }
  let runtime_manifest = "\{workspace}/moonbit-runtime.sha256"
  guard @fs.exists(runtime_manifest) else {
    @cli.fail_cli(
      "the device workspace has no runtime manifest: \{runtime_manifest}",
    )
  }
  match verify_runtime_sha256(runtime_manifest) {
    Some(problem) =>
      @cli.fail_cli(
        "the pinned MoonBit runtime under MOON_HOME does not match the host manifest: \{problem}",
      )
    None => ()
  }
  // The moonbit_runtime CMake component reads $MOON_HOME directly, so the
  // resolved location must cross into the idf env even when the invoking
  // shell never exported it.
  let moon_home = moon_home_dir()
  run_step(
    @shell.Cmd::Cmd("idf.py", ["reconfigure"], cwd=workspace, env={
      "IDF_TARGET": "esp32c3",
      "MOON_HOME": moon_home,
    }),
    "configuring firmware (idf.py reconfigure)",
  )
  let sdkconfig = "\{workspace}/sdkconfig"
  guard @fs.exists(sdkconfig) else {
    @cli.fail_cli("idf.py reconfigure produced no sdkconfig at \{sdkconfig}")
  }
  let config_text = read_text_file(sdkconfig)
  for
    baseline in [
      "CONFIG_FREERTOS_HZ=1000", "CONFIG_PARTITION_TABLE_CUSTOM=y", "CONFIG_PARTITION_TABLE_CUSTOM_FILENAME=\"partitions.csv\"",
    ] {
    guard config_has_line(config_text, baseline) else {
      @cli.fail_cli(
        "the effective sdkconfig misses the device baselines (CONFIG_FREERTOS_HZ=1000, CONFIG_PARTITION_TABLE_CUSTOM=y, CONFIG_PARTITION_TABLE_CUSTOM_FILENAME=\"partitions.csv\"); delete \{sdkconfig} and rebuild",
      )
    }
  }
  run_step(
    @shell.Cmd::Cmd("idf.py", ["build"], cwd=workspace, env={
      "IDF_TARGET": "esp32c3",
      "MOON_HOME": moon_home,
    }),
    "building firmware (idf.py build)",
  )
  let firmware = "\{workspace}/build/ai_passport_app.bin"
  guard @fs.exists(firmware) else {
    @cli.fail_cli("idf.py build finished but \{firmware} is missing")
  }
  let size = @fs.file_size(firmware)
  println("passport: firmware built at \{firmware}")
  println("passport: size: \{size} bytes")
  println(
    "passport: app partition margin: \{APP_PARTITION_SIZE - size} bytes (partition size 0x380000)",
  )
  println("passport: workspace: \{workspace}")
}
