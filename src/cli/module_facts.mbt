///|
/// Pure module-file fact scanning and path derivation (no I/O).

///|
/// Extracts a quoted scalar assignment from moon.mod text (for example
/// `name = "colmugx/ai-passport"`). Returns None when absent.
pub fn moon_mod_scalar(mod_text : String, key : String) -> String? {
  let needle = "\{key} = \""
  for line in mod_text.split("\n").to_array() {
    let trimmed = line.trim()
    if trimmed.has_prefix(needle) {
      let rest = trimmed[needle.length():]
      match rest.find("\"") {
        Some(end) => return Some(rest[:end].to_owned())
        None => return None
      }
    }
  }
  None
}

///|
/// Extracts the pinned SDK dependency version from moon.mod text
/// (`"colmugx/ai-passport@X.Y.Z"` inside the import block).
pub fn sdk_dependency_version(mod_text : String) -> String? {
  let needle = "\"colmugx/ai-passport@"
  for line in mod_text.split("\n").to_array() {
    match line.find(needle) {
      Some(at) => {
        let rest = line[at + needle.length():]
        match rest.find("\"") {
          Some(end) => return Some(rest[:end].to_owned())
          None => return None
        }
      }
      None => ()
    }
  }
  None
}

///|
/// Joins a project-root path with a module-relative path ("" relative means
/// the root itself).
pub fn under_root(root : String, relative : String) -> String {
  if relative == "" {
    root
  } else if root.has_suffix("/") {
    "\{root}\{relative}"
  } else {
    "\{root}/\{relative}"
  }
}

///|
/// The module source root as a filesystem path.
pub fn source_root(project : Project) -> String {
  under_root(project.root, project.source_dir)
}

///|
/// Filesystem path of the entry package directory.
pub fn entry_package_dir(project : Project) -> String {
  under_root(source_root(project), project.contract.entry)
}

///|
/// Filesystem path of the expected release wasm artifact for the entry
/// package: `_build/wasm/release/build/<entry>/<entry basename>.wasm`.
pub fn expected_wasm_artifact(project : Project) -> String {
  let entry = project.contract.entry
  let base = match entry.rev_find("/") {
    Some(at) => entry[at + 1:].to_owned()
    None => entry
  }
  under_root(project.root, "_build/wasm/release/build/\{entry}/\{base}.wasm")
}

///|
/// The bundle directory contract: everything a Host needs to serve the
/// application, assembled under the project root.
pub const BUNDLE_DIR : String = ".passport/web"

///|
/// The three files a Web Host bundle needs from the SDK.
pub fn sdk_host_files() -> Array[String] {
  ["index.html", "passport-host.js", "pcm-worklet.js"]
}
