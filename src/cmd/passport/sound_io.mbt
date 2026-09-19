///|
/// Loads every declared PCM source through the project ownership boundary,
/// then invokes the one filesystem-free compiler shared by all Host builds.
/// The configured relative source is retained in metadata; only the file read
/// follows its canonical path after containment has been proven.
async fn compile_project_sounds(
  project : @cli.Project,
) -> @cli.SoundCompilation {
  let inputs : Array[@cli.SoundInput] = []
  for sound in project.contract.sounds {
    let source = @cli.under_root(project.root, sound.source)
    guard @fs.exists(source) else {
      @cli.fail_cli("sound source is missing: \{sound.source}")
    }
    let resolved = @fs.realpath(source) catch {
      _ => @cli.fail_cli("cannot resolve sound source: \{sound.source}")
    }
    guard resolved != project.root && path_is_within(project.root, resolved) else {
      @cli.fail_cli(
        "sound source resolves outside the project root: \{sound.source}",
      )
    }
    guard @fs.kind(resolved) is Regular else {
      @cli.fail_cli("sound source is not a file: \{sound.source}")
    }
    let pcm = @fs.read_file(resolved).binary() catch {
      _ => @cli.fail_cli("cannot read sound source: \{sound.source}")
    }
    inputs.push({ entry: sound, pcm, })
  }
  @cli.compile_sounds(inputs)
}

///|
async fn write_sound_bank(
  path : String,
  compilation : @cli.SoundCompilation,
) -> Unit {
  @fs.write_file(path, compilation.bank) catch {
    _ => @cli.fail_cli("cannot write sound bank to \{path}")
  }
}
