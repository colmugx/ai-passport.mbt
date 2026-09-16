///|
/// `passport dev --host <id>`: build the bundle, then serve it over local
/// HTTP and print the final URL. The server is an unmodified `python3 -m
/// http.server` bound to the loopback interface — no npm dependency, no
/// application-specific routing; the SDK Web Host page runs the app.

///|
const DEV_DEFAULT_PORT : String = "8000"

///|
/// Parses a decimal TCP port in the 1..=65535 range.
fn parse_port(text : String) -> Int? {
  if text == "" {
    return None
  }
  let mut value = 0
  for ch in text {
    if ch < '0' || ch > '9' {
      return None
    }
    value = value * 10 + (ch.to_int() - '0'.to_int())
    if value > 65535 {
      return None
    }
  }
  Some(value)
}

///|
async fn dev_command(sub : @argparse.Matches) -> Unit {
  let host_id = option_value(sub, "host", "web")
  let descriptor = @cli.require_implemented_host(host_id)
  // The dev server serves the Web Host bundle; other implemented Hosts are
  // built, not served.
  guard descriptor.id == "web" else {
    @cli.fail_cli(
      "host \"\{host_id}\" has no dev server; use `passport build --host \{host_id}`",
    )
  }
  let port_text = option_value(sub, "port", DEV_DEFAULT_PORT)
  let port = match parse_port(port_text) {
    Some(value) => value
    None =>
      @cli.fail_cli(
        "--port must be a number between 1 and 65535 (got \{port_text})",
      )
  }
  let project = load_project(option_value(sub, "project", "."))
  // The dev build is exactly the build command.
  build_command(sub)
  let entry = "/\{@cli.entry_url_path(project.contract)}"
  println("")
  println("passport: serving \{@cli.under_root(project.root, @cli.BUNDLE_DIR)}")
  println("passport: URL: http://127.0.0.1:\{port}\{entry}")
  println("passport: Press Ctrl-C to stop.")
  // Serve until interrupted; the server shares the process group, so Ctrl-C
  // stops both the CLI and the server.
  run_step(
    @shell.Cmd::Cmd(
      "python3",
      [
        "-m",
        "http.server",
        port.to_string(),
        "--bind",
        "127.0.0.1",
        "--directory",
        @cli.BUNDLE_DIR,
      ],
      cwd=project.root,
    ),
    "serving the bundle (python3 http.server)",
  )
}
