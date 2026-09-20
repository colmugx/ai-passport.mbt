///|
/// Normalizes a Rule path emitted by Moon. Rule inputs and outputs are
/// module-root-relative; absolute paths and traversal are not part of this
/// command's contract.
fn normalize_rule_path(path : String, label : String) -> String raise {
  let path = if path.has_prefix("./") { path[2:].to_owned() } else { path }
  guard path != "" && !path.has_prefix("/") else {
    @cli.fail_cli(
      "generate-sounds \{label} must be relative to the module root",
    )
  }
  guard path.find("\\") is None else {
    @cli.fail_cli("generate-sounds \{label} must use forward slashes")
  }
  for part in path.split("/").to_array() {
    if part == "" || part == "." || part == ".." {
      @cli.fail_cli(
        "generate-sounds \{label} contains an unsafe path component",
      )
    }
  }
  path
}

///|
/// Resolves the Rule output selected by dev_build. The destination package is
/// application-owned and may have any package name; this command owns only the
/// exact .mbt file supplied as its output.
async fn validate_sound_mapping_paths(
  project : @cli.Project,
  input : String,
  output : String,
) -> String {
  let input = normalize_rule_path(input, "input")
  guard input == "passport.toml" else {
    @cli.fail_cli(
      "generate-sounds input must be the project's root passport.toml",
    )
  }
  let output = normalize_rule_path(output, "output")
  guard output.has_suffix(".mbt") else {
    @cli.fail_cli("generate-sounds output must be a .mbt source file")
  }
  let output_parts = output.split("/").to_array()
  guard output_parts.length() > 1 else {
    @cli.fail_cli("generate-sounds output must belong to a MoonBit package")
  }
  let filename = output_parts[output_parts.length() - 1].to_owned()
  let package_relative = StringBuilder(size_hint=output.length())
  for index in 0..<(output_parts.length() - 1) {
    if index > 0 {
      package_relative.write_char('/')
    }
    package_relative.write_string(output_parts[index].to_owned())
  }
  let source_root = @fs.realpath(@cli.source_root(project)) catch {
    _ => @cli.fail_cli("cannot resolve the module source root")
  }
  let package_dir = "\{project.root}/\{package_relative}"
  guard @fs.exists("\{package_dir}/moon.pkg") else {
    @cli.fail_cli(
      "sound mapping output package is missing moon.pkg at \{package_dir}",
    )
  }
  let package_root = @fs.realpath(package_dir) catch {
    _ => @cli.fail_cli("cannot resolve sound mapping package at \{package_dir}")
  }
  guard package_root != source_root && path_is_within(source_root, package_root) else {
    @cli.fail_cli(
      "sound mapping output package resolves outside the module source root",
    )
  }
  let path = "\{package_root}/\{filename}"
  let entries = @fs.readdir(package_root) catch {
    _ =>
      @cli.fail_cli("cannot inspect sound mapping package at \{package_root}")
  }
  if entries.contains(filename) {
    let output_kind = @fs.kind(path, follow_symlink=false) catch {
      _ => @cli.fail_cli("cannot inspect generated sound mapping at \{path}")
    }
    match output_kind {
      SymLink =>
        @cli.fail_cli("generated sound mapping must not be a symbolic link")
      Regular => {
        let resolved = @fs.realpath(path) catch {
          _ =>
            @cli.fail_cli("cannot resolve generated sound mapping at \{path}")
        }
        guard path_is_strictly_within(package_root, resolved) else {
          @cli.fail_cli("generated sound mapping resolves outside its package")
        }
      }
      _ => @cli.fail_cli("generated sound mapping is not a regular file")
    }
  }
  path
}

///|
/// passport generate-sounds INPUT OUTPUT: the command invoked by the
/// application's Rule/dev_build. It uses the same metadata compiler as final
/// Host builds and writes exactly the Rule output selected by the package.
async fn generate_sounds_command(input : String, output : String) -> Unit {
  let project = load_project(".")
  let path = validate_sound_mapping_paths(project, input, output)
  let metadata = @cli.compile_sound_metadata(project.contract.sounds)
  write_generated_file(path, @cli.render_sound_mapping(metadata))
  println("passport: generated sound mapping at \{path}")
}
