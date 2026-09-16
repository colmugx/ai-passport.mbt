///|
/// `passport doctor`: dependency checks for the requested Host. Only the
/// dependencies of the requested operation are checked — Web development
/// never requires device tooling. An unimplemented Host backend is reported
/// as such instead of inventing support.

///|
async fn doctor_command(sub : @argparse.Matches) -> Unit {
  let host_id = option_value(sub, "host", "web")
  let descriptor = @cli.require_known_host(host_id)
  println("passport doctor — host: \{host_id}")
  println("  \{descriptor.summary}")
  match descriptor.backend {
    @hosts.NotMigrated(reason) => {
      for fact in descriptor.facts {
        println("  fact: \{fact}")
      }
      @cli.fail_cli(
        "host \"\{host_id}\" \{reason}; there is nothing to check yet",
      )
    }
    @hosts.Implemented => ()
  }
  let failures : Array[String] = []

  let moon_out = @shell.Cmd::Cmd("moon", ["version"]).output()
  if moon_out.exit_code() == 0 {
    let stdout = moon_out.stdout()
    let first_line = match stdout.find("\n") {
      Some(at) => stdout[:at].to_owned()
      None => stdout
    }
    println("ok: moon toolchain (\{first_line.trim()})")
  } else {
    println("FAIL: the moon toolchain is unavailable")
    failures.push("moon toolchain")
  }

  let project_dir = option_value(sub, "project", ".")
  let mut loaded : @cli.Project? = None
  try {
    loaded = Some(load_project(project_dir))
  } catch {
    @cli.Fail(message) => {
      println("FAIL: \{message}")
      failures.push("project contract")
    }
    _ => {
      println("FAIL: unexpected error while reading the project")
      failures.push("project contract")
    }
  }
  match loaded {
    Some(project) => {
      let entry_dir = @cli.entry_package_dir(project)
      if @fs.exists("\{entry_dir}/moon.pkg") {
        println(
          "ok: entry package \"\{project.contract.entry}\" found under the module source root",
        )
      } else {
        println(
          "FAIL: entry package \"\{project.contract.entry}\" not found (\{entry_dir})",
        )
        failures.push("entry package")
      }
      let mut sdk_dir : String? = None
      try {
        sdk_dir = Some(resolve_sdk_package_dir(project))
      } catch {
        @cli.Fail(message) => {
          println("FAIL: \{message}")
          failures.push("SDK Web Host assets")
        }
        _ => {
          println(
            "FAIL: unexpected error while locating the SDK Web Host assets",
          )
          failures.push("SDK Web Host assets")
        }
      }
      match sdk_dir {
        Some(dir) => println("ok: SDK Web Host assets at \{dir}")
        None => ()
      }
    }
    None => ()
  }

  let python_out = @shell.Cmd::Cmd("python3", ["--version"]).output()
  if python_out.exit_code() == 0 {
    println("ok: python3 static server (\{python_out.stdout().trim()})")
  } else {
    println("FAIL: python3 is required by `passport dev --host web`")
    failures.push("python3")
  }
  if failures.length() > 0 {
    @cli.fail_cli("doctor found \{failures.length()} failing check(s)")
  }
  println("doctor: all checks passed")
}
