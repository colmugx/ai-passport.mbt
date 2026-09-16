///|
/// The minimal downstream project contract (machine-readable `passport.json`
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
pub(all) struct ProjectContract {
  /// Application entry package path, relative to the module source root
  /// (the package whose moon.pkg exports the passport_* wasm symbols).
  entry : String
  /// Files to materialize into the bundle; may be empty.
  assets : Array[AssetEntry]
} derive(Eq, Debug)

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
    fail_cli("passport.json: \{field} must not be empty")
  }
  guard !value.has_prefix("/") else {
    fail_cli("passport.json: \{field} must be relative")
  }
  guard value.find("\\") is None else {
    fail_cli("passport.json: \{field} must use forward slashes")
  }
  for part in value.split("/").to_array() {
    if part == "" || part == "." || part == ".." {
      fail_cli("passport.json: \{field} contains an unsafe path component")
    }
  }
}

///|
fn reserved_bundle_path(path : String) -> Bool {
  path == "app.wasm" || path == "index.html" ||
  path == "passport-host.js" || path == "pcm-worklet.js"
}

///|
/// Parses the contract JSON text. Pure (no filesystem access).
pub fn parse_contract(text : String) -> ProjectContract raise {
  let value = @json.parse(text) catch {
    _ => fail_cli("passport.json: not valid JSON")
  }
  guard value is Object(root) else {
    fail_cli("passport.json: the top level must be a JSON object")
  }
  let entry = match root.get("entry") {
    Some(String(entry)) => entry
    Some(_) => fail_cli("passport.json: \"entry\" must be a string")
    None =>
      fail_cli(
        "passport.json: missing required field \"entry\" (the application wasm entry package)",
      )
  }
  validate_relative_path(entry, "\"entry\"")
  let assets : Array[AssetEntry] = []
  match root.get("assets") {
    Some(Array(list)) =>
      for raw in list {
        let asset = parse_asset(raw)
        for existing in assets {
          if existing.bundle_path == asset.bundle_path {
            fail_cli(
              "passport.json: duplicate asset \"bundlePath\" \"\{asset.bundle_path}\"",
            )
          }
        }
        assets.push(asset)
      }
    Some(_) => fail_cli("passport.json: \"assets\" must be an array")
    None => ()
  }
  let pcm_assets = assets.filter(fn(a) { a.pcm_loop })
  if pcm_assets.length() > 1 {
    fail_cli(
      "passport.json: at most one asset may set \"pcmLoop\": true (found \{pcm_assets.length()})",
    )
  }
  { entry, assets, }
}

///|
fn parse_asset(value : Json) -> AssetEntry raise {
  guard value is Object(obj) else {
    fail_cli("passport.json: each asset must be an object")
  }
  guard obj.get("source") is Some(String(source)) else {
    fail_cli("passport.json: asset is missing required field \"source\"")
  }
  guard obj.get("bundlePath") is Some(String(bundle_path)) else {
    fail_cli("passport.json: asset is missing required field \"bundlePath\"")
  }
  validate_relative_path(source, "asset \"source\"")
  validate_relative_path(bundle_path, "asset \"bundlePath\"")
  guard !reserved_bundle_path(bundle_path) else {
    fail_cli(
      "passport.json: asset \"bundlePath\" \"\{bundle_path}\" is reserved by the Web Host",
    )
  }
  let pcm_loop = match obj.get("pcmLoop") {
    Some(True) => true
    Some(False) => false
    Some(_) => fail_cli("passport.json: asset \"pcmLoop\" must be a boolean")
    None => false
  }
  { source, bundle_path, pcm_loop, }
}
