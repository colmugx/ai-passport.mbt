///|
/// The passport CLI: build, serve and inspect AI Passport applications
/// against registered Hosts. The Host is the only backend abstraction; there
/// is no application-specific knowledge in this CLI — projects describe
/// themselves through `passport.toml` (the contract lives in `src/cli`).

///|
/// Reads one option value from parsed matches, falling back to `default`.
fn option_value(
  matches : @argparse.Matches,
  name : String,
  default : String,
) -> String {
  match matches.values.get(name) {
    Some(values) => if values.length() > 0 { values[0] } else { default }
    None => default
  }
}

///|
fn build_cli() -> @argparse.Command {
  let host_option = @argparse.OptionArg::OptionArg(
    "host",
    long="host",
    about="Registered Host to operate on (see `passport hosts`).",
    action=@argparse.OptionAction::Set,
    default_values=["web"],
  )
  let project_option = @argparse.OptionArg::OptionArg(
    "project",
    long="project",
    about="Application project directory (default: the current directory).",
    action=@argparse.OptionAction::Set,
    default_values=["."],
  )
  let hosts_cmd = @argparse.Command::Command(
    "hosts",
    about="List the registered Hosts and their capabilities.",
  )
  let doctor_cmd = @argparse.Command::Command(
    "doctor",
    about="Check the dependencies needed to work with one Host.",
    options=[host_option, project_option],
  )
  let build_cmd = @argparse.Command::Command(
    "build",
    about="Build the application bundle for one Host.",
    options=[host_option, project_option],
  )
  let generate_sounds_cmd = @argparse.Command::Command(
    "generate-sounds",
    about="Generate the typed @sounds mapping used by Moon Rule/dev_build.",
    positionals=[
      @argparse.PositionArg::PositionArg(
        "input",
        about="Rule input: the project's passport.toml.",
        num_args=@argparse.ValueRange::single(),
      ),
      @argparse.PositionArg::PositionArg(
        "output",
        about="Rule output: a .mbt file in the invoking package.",
        num_args=@argparse.ValueRange::single(),
      ),
    ],
  )
  let dev_cmd = @argparse.Command::Command(
    "dev",
    about="Build the bundle, serve it over local HTTP and print the URL.",
    options=[
      host_option,
      project_option,
      @argparse.OptionArg::OptionArg(
        "port",
        long="port",
        about="TCP port for the dev server.",
        action=@argparse.OptionAction::Set,
        default_values=["8000"],
      ),
    ],
  )
  @argparse.Command::Command(
    "passport",
    about="AI Passport application platform CLI. The only backend abstraction is the Host.",
    subcommands=[hosts_cmd, doctor_cmd, build_cmd, dev_cmd, generate_sounds_cmd],
  )
}

///|
async fn main {
  let args = @env.args()
  let rest = if args.length() > 1 { args[1:].to_owned() } else { [] }
  let cmd = build_cli()
  if rest.length() == 0 {
    println(cmd.render_help())
    @cli.fail_cli(
      "a subcommand is required (hosts, doctor, build, dev, generate-sounds)",
    )
  }
  let matches = cmd.parse(argv=rest[:])
  guard matches.subcommand is Some((name, sub)) else {
    println(cmd.render_help())
    @cli.fail_cli(
      "a subcommand is required (hosts, doctor, build, dev, generate-sounds)",
    )
  }
  try {
    match name {
      "hosts" => hosts_command()
      "doctor" => doctor_command(sub)
      "build" => build_command(sub)
      "dev" => dev_command(sub)
      "generate-sounds" =>
        generate_sounds_command(
          option_value(sub, "input", ""),
          option_value(sub, "output", ""),
        )
      unknown => @cli.fail_cli("unknown subcommand \"\{unknown}\"")
    }
  } catch {
    @cli.Fail(message) => {
      @stdio.stderr.write(@utf8.encode("passport: \{message}\n"))
      raise @cli.Fail(message)
    }
    err => {
      @stdio.stderr.write(@utf8.encode("passport: unexpected error: \{err}\n"))
      raise err
    }
  }
}
