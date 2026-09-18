///|
/// Filesystem-boundary checks for project-owned paths. Keep these private to
/// the CLI executable package: they protect destructive operations but are not
/// part of the reusable SDK surface.

///|
/// Validates moon.mod's optional source directory before it participates in
/// any filesystem path. Empty means packages live at the module root.
fn validate_module_source_dir(source_dir : String) -> Unit raise {
  if source_dir == "" {
    return
  }
  guard !source_dir.has_prefix("/") else {
    @cli.fail_cli("moon.mod: source must be a relative path inside the project")
  }
  guard source_dir.find("\\") is None else {
    @cli.fail_cli("moon.mod: source must use forward slashes")
  }
  for part in source_dir.split("/").to_array() {
    if part == "" || part == "." || part == ".." {
      @cli.fail_cli("moon.mod: source contains an unsafe path component")
    }
  }
}

///|
/// True when `path` is `root` itself or a descendant on a path-component
/// boundary. Both inputs must already be canonical absolute paths.
fn path_is_within(root : String, path : String) -> Bool {
  if path == root {
    return true
  }
  let prefix = if root.has_suffix("/") { root } else { "\{root}/" }
  path.has_prefix(prefix)
}
