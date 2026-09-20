///|
/// Refuses missing package setup and symlink escapes before writing the Rule
/// output. The package directory and its moon.pkg are application-owned; only
/// generated.mbt is generated.
async fn validate_sound_mapping_output(project : @cli.Project) -> String {
  let source_root = @fs.realpath(@cli.source_root(project)) catch {
    _ => @cli.fail_cli("cannot resolve the module source root")
  }
  let package_dir = "\{source_root}/sounds"
  guard @fs.exists("\{package_dir}/moon.pkg") else {
    @cli.fail_cli("sound mapping package is missing moon.pkg at \{package_dir}")
  }
  let package_root = @fs.realpath(package_dir) catch {
    _ => @cli.fail_cli("cannot resolve sound mapping package at \{package_dir}")
  }
  guard package_root != source_root && path_is_within(source_root, package_root) else {
    @cli.fail_cli(
      "sound mapping package resolves outside the module source root",
    )
  }
  let path = "\{package_dir}/generated.mbt"
  let entries = @fs.readdir(package_root) catch {
    _ =>
      @cli.fail_cli("cannot inspect sound mapping package at \{package_root}")
  }
  if entries.contains("generated.mbt") {
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
/// `passport generate-sounds`: the command invoked by the application's
/// Rule/dev_build. It uses the same metadata compiler as final Host builds.
async fn generate_sounds_command() -> Unit {
  let project = load_project(".")
  let path = validate_sound_mapping_output(project)
  let metadata = @cli.compile_sound_metadata(project.contract.sounds)
  write_generated_file(path, @cli.render_sound_mapping(metadata))
  println("passport: generated sound mapping at \{path}")
}
