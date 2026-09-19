///|
/// The minimal downstream project contract (machine-readable `passport.toml`
/// at the project root). It answers exactly what generic tooling needs to
/// build a Host bundle: which application package is the wasm entry, and
/// which project files to materialize into the bundle. Deliberately small —
/// device backends and richer manifests are later rounds.

///|
/// One file to materialize into the bundle.
pub(all) struct AssetEntry {
  /// Path relative to the project root.
  source : String
  /// Destination path relative to the bundle root (`.passport/web/`).
  bundle_path : String
  /// When true, this asset is the Host's normalized PCM playback asset: the
  /// dev/build entry URL carries `?pcm=<bundle_path>&pcmLoop=1`. At most one
  /// asset per project may set it.
  pcm_loop : Bool
} derive(Eq, Debug)

///|
/// One external dependency a Host build consumes outside the SDK release
/// (for example a pinned hardware vendor checkout). The SDK never carries
/// or publishes this code; the path is project-provided and points at a
/// checkout the project owns (a git submodule in the reference template).
pub(all) struct HostDependency {
  /// Host id this dependency is declared for (a registered Host).
  host_id : String
  /// Checkout location, relative to the project root.
  path : String
} derive(Eq, Debug)

///|
pub(all) struct ProjectContract {
  /// Application entry package path, relative to the module source root
  /// (the package whose moon.pkg exports the passport_* wasm symbols).
  entry : String
  /// Optional device entry package path, relative to the module source root
  /// (the native foreign-library package a physical Host builds). Absent
  /// means the project declares no device entry yet.
  device_entry : String?
  /// Files to materialize into the bundle; may be empty.
  assets : Array[AssetEntry]
  /// Project-provided external Host dependencies; may be empty.
  host_dependencies : Array[HostDependency]
} derive(Eq, Debug)

///|
/// Location of the project-provided checkout for `host_id`, when declared.
pub fn host_dependency_path(
  contract : ProjectContract,
  host_id : String,
) -> String? {
  for dep in contract.host_dependencies {
    if dep.host_id == host_id {
      return Some(dep.path)
    }
  }
  None
}

///|
/// An application project: its root, its module facts, and its contract.
pub(all) struct Project {
  /// Absolute project root (the directory holding moon.mod).
  root : String
  /// Module name from moon.mod (for example `colmugx/ai-passport-template`).
  module_name : String
  /// Module source directory from moon.mod ("" when packages live at the
  /// module root, "src" for the common layout).
  source_dir : String
  contract : ProjectContract
} derive(Eq, Debug)

///|
/// Contract paths are portable, project-relative slash paths. Reject
/// traversal and platform-specific separators before any filesystem access.
fn validate_relative_path(value : String, field : String) -> Unit raise {
  guard value != "" else {
    fail_cli("passport.toml: \{field} must not be empty")
  }
  guard !value.has_prefix("/") else {
    fail_cli("passport.toml: \{field} must be relative")
  }
  guard value.find("\\") is None else {
    fail_cli("passport.toml: \{field} must use forward slashes")
  }
  for part in value.split("/").to_array() {
    if part == "" || part == "." || part == ".." {
      fail_cli("passport.toml: \{field} contains an unsafe path component")
    }
  }
}

///|
fn reserved_bundle_path(path : String) -> Bool {
  path == "app.wasm" ||
  path == "index.html" ||
  path == "passport-host.js" ||
  path == "pcm-worklet.js"
}

///|
/// Whether an entry package's `moon.pkg` text declares an executable
/// package. That is the legacy (published 0.0.5) entry contract: the entry
/// itself is the Wasm executable exporting the `passport_*` ABI symbols and
/// `deviceEntry` names a separate native entry. A library entry instead
/// implements the application contract and the CLI generates every Host
/// entry around it.
fn config_argument_after(statement : String, key : String) -> String? {
  match statement.find("(") {
    Some(open) =>
      for part in statement[open + 1:].split(",").to_array() {
        match part.find(":") {
          Some(at) =>
            if part[:at].trim() == key {
              return Some(part[at + 1:].trim().to_owned())
            }
          None => ()
        }
      }
    None => ()
  }
  None
}

///|
/// Detects only actual package declarations, not words that happen to occur
/// in comments, descriptions, import paths or unrelated option values.
/// Moon's current form is `pkgtype(kind: "executable")`; the legacy
/// `options("is-main": true)` form remains accepted for published 0.0.5
/// projects.
pub fn entry_is_executable_package(pkg_text : String) -> Bool {
  let mut statement = ""
  let mut statement_kind = 0
  for raw_line in pkg_text.split("\n").to_array() {
    let trimmed = strip_config_line_comment(raw_line.to_owned()).trim()
    if trimmed == "" {
      continue
    }
    if statement_kind == 0 {
      if trimmed.has_prefix("pkgtype(") {
        statement_kind = 1
      } else if trimmed.has_prefix("options(") {
        statement_kind = 2
      } else {
        continue
      }
      statement = trimmed.to_owned()
    } else {
      statement = "\{statement}\{trimmed}"
    }

    if statement.contains(")") {
      if statement_kind == 1 {
        match config_argument_after(statement, "kind") {
          Some(value) => if value.has_prefix("\"executable\"") { return true }
          None => ()
        }
      } else {
        match config_argument_after(statement, "\"is-main\"") {
          Some(value) => if value.has_prefix("true") { return true }
          None => ()
        }
      }
      statement = ""
      statement_kind = 0
    }
  }
  false
}

///|
/// Parses the project contract TOML text. Pure (no filesystem access).
pub fn parse_contract(text : String) -> ProjectContract raise {
  let value = @toml.parse(text) catch {
    _ => fail_cli("passport.toml: not valid TOML")
  }
  guard value is @toml.TomlTable(root) else {
    fail_cli("passport.toml: the top level must be a TOML table")
  }
  let entry = match root.get("entry") {
    Some(@toml.TomlString(entry)) => entry
    Some(_) => fail_cli("passport.toml: \"entry\" must be a string")
    None =>
      fail_cli(
        "passport.toml: missing required field \"entry\" (the application wasm entry package)",
      )
  }
  validate_relative_path(entry, "\"entry\"")
  let device_entry = match root.get("deviceEntry") {
    Some(@toml.TomlString(device_entry)) => {
      validate_relative_path(device_entry, "\"deviceEntry\"")
      Some(device_entry)
    }
    Some(_) => fail_cli("passport.toml: \"deviceEntry\" must be a string")
    None => None
  }
  let assets : Array[AssetEntry] = []
  match root.get("assets") {
    Some(@toml.TomlArray(list)) =>
      for raw in list {
        let asset = parse_asset(raw)
        for existing in assets {
          if existing.bundle_path == asset.bundle_path {
            fail_cli(
              "passport.toml: duplicate asset \"bundlePath\" \"\{asset.bundle_path}\"",
            )
          }
        }
        assets.push(asset)
      }
    Some(_) => fail_cli("passport.toml: \"assets\" must be an array")
    None => ()
  }
  let pcm_assets = assets.filter(fn(a) { a.pcm_loop })
  if pcm_assets.length() > 1 {
    fail_cli(
      "passport.toml: at most one asset may set \"pcmLoop\": true (found \{pcm_assets.length()})",
    )
  }
  let host_dependencies : Array[HostDependency] = []
  match root.get("hostDependencies") {
    Some(@toml.TomlTable(map)) =>
      for (key, raw) in map {
        guard raw is @toml.TomlTable(dep) else {
          fail_cli(
            "passport.toml: hostDependencies[\"\{key}\"] must be a table",
          )
        }
        guard dep.get("path") is Some(@toml.TomlString(path)) else {
          fail_cli(
            "passport.toml: hostDependencies[\"\{key}\"] is missing required string field \"path\"",
          )
        }
        validate_relative_path(path, "hostDependencies[\"\{key}\"].\"path\"")
        host_dependencies.push({ host_id: key, path, })
      }
    Some(_) => fail_cli("passport.toml: \"hostDependencies\" must be a table")
    None => ()
  }
  { entry, device_entry, assets, host_dependencies, }
}

///|
fn parse_asset(value : @toml.TomlValue) -> AssetEntry raise {
  guard value is @toml.TomlTable(obj) else {
    fail_cli("passport.toml: each asset must be a table")
  }
  guard obj.get("source") is Some(@toml.TomlString(source)) else {
    fail_cli("passport.toml: asset is missing required string field \"source\"")
  }
  guard obj.get("bundlePath") is Some(@toml.TomlString(bundle_path)) else {
    fail_cli(
      "passport.toml: asset is missing required string field \"bundlePath\"",
    )
  }
  validate_relative_path(source, "asset \"source\"")
  validate_relative_path(bundle_path, "asset \"bundlePath\"")
  guard !reserved_bundle_path(bundle_path) else {
    fail_cli(
      "passport.toml: asset \"bundlePath\" \"\{bundle_path}\" is reserved by the Web Host",
    )
  }
  let pcm_loop = match obj.get("pcmLoop") {
    Some(@toml.TomlBoolean(value)) => value
    Some(_) => fail_cli("passport.toml: asset \"pcmLoop\" must be a boolean")
    None => false
  }
  { source, bundle_path, pcm_loop, }
}
