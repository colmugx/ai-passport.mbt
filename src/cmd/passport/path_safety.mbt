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

///|
fn path_is_strictly_within(root : String, path : String) -> Bool {
  path != root && path_is_within(root, path)
}

///|
/// Canonicalizes an owner root and one existing target immediately before a
/// recursive delete. The target must be a strict descendant of the owner;
/// deleting the owner itself or following an escaping symlink is refused.
async fn remove_owned_tree(
  owner_path : String,
  target_path : String,
  what : String,
) -> Unit {
  let owner_root = @fs.realpath(owner_path) catch {
    _ => @cli.fail_cli("cannot resolve ownership root at \{owner_path}")
  }
  let target_root = @fs.realpath(target_path) catch {
    _ => @cli.fail_cli("cannot resolve \{what} at \{target_path}")
  }
  guard path_is_strictly_within(owner_root, target_root) else {
    @cli.fail_cli(
      "refusing to remove \{what} outside its owned root \{owner_path}",
    )
  }
  @fs.rmdir(target_path, recursive=true) catch {
    _ => @cli.fail_cli("cannot remove \{what} at \{target_path}")
  }
}
