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
  if host_id == "folotoy-ai-passport" {
    doctor_device(sub)
    return
  }
  let failures : Array[String] = []

  let moon_out = @shell.Cmd::Cmd("moon", ["version"]).output()
  let moon_available = moon_out.exit_code() == 0
  if moon_available {
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
      doctor_sound_resources(project, failures)
      let entry_dir = @cli.entry_package_dir(project)
      let entry_exists = @fs.exists("\{entry_dir}/moon.pkg")
      if entry_exists {
        println(
          "ok: entry package \"\{project.contract.entry}\" found under the module source root",
        )
      } else {
        println(
          "FAIL: entry package \"\{project.contract.entry}\" not found (\{entry_dir})",
        )
        failures.push("entry package")
      }
      // `moon check` is the supported project operation that validates the
      // entry and materializes declared dependencies as needed. Do not depend
      // on a deprecated no-argument installer or Moon's private global cache.
      let mut dependencies_ready = false
      if moon_available && entry_exists {
        let check = @shell.Cmd::Cmd(
          "moon",
          ["check", entry_dir, "--target", "wasm"],
          cwd=project.root,
        ).output()
        if check.exit_code() == 0 {
          println("ok: application entry resolves for wasm")
          dependencies_ready = true
        } else {
          println(
            "FAIL: moon check could not resolve/check the application entry",
          )
          failures.push("application dependencies")
        }
      }
      if dependencies_ready {
        let mut sdk_dir : String? = None
        try {
          sdk_dir = Some(
            resolve_sdk_host_dir(project, SDK_HOST_DIR, @cli.sdk_host_files()),
          )
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

///|
/// Validates the same canonical paths, PCM bytes and APSB serialization used
/// by real builds. Doctor reports the failure and continues with independent
/// checks instead of maintaining a weaker, duplicated sound validator.
async fn doctor_sound_resources(
  project : @cli.Project,
  failures : Array[String],
) -> Unit {
  try {
    let compilation = compile_project_sounds(project)
    println(
      "ok: \{compilation.sounds.length()} sound resource(s), \{compilation.bank.length()} bank bytes",
    )
  } catch {
    @cli.Fail(message) => {
      println("FAIL: \{message}")
      failures.push("sound resources")
    }
    _ => {
      println("FAIL: unexpected error while validating sound resources")
      failures.push("sound resources")
    }
  }
}

///|
/// Device doctor: verifies the pinned physical-Host toolchain and the
/// project's device contract. Every failed check is recorded and reported at
/// the end; nothing aborts early.
async fn doctor_device(sub : @argparse.Matches) -> Unit {
  let failures : Array[String] = []
  match try_output(@shell.Cmd::Cmd("idf.py", ["--version"])) {
    None => {
      println(
        "FAIL: idf.py is unavailable; source the \{IDF_VERSION_PIN} export.sh",
      )
      failures.push("ESP-IDF toolchain")
    }
    Some(out) => {
      let first = first_line(out.stdout()).trim()
      if first.contains(IDF_VERSION_PIN) {
        println("ok: ESP-IDF toolchain (\{first})")
      } else {
        println(
          "FAIL: expected \{IDF_VERSION_PIN}; source the matching export.sh (got \{first})",
        )
        failures.push("ESP-IDF toolchain")
      }
    }
  }
  let mut loaded : @cli.Project? = None
  try {
    loaded = Some(load_project(option_value(sub, "project", ".")))
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
    Some(project) =>
      match project.contract.device_entry {
        Some(entry) => doctor_device_project(project, entry, failures)
        None => {
          // Without a declared `deviceEntry`, a library application entry
          // gets the generated FoloToy adapter; a legacy executable entry
          // (the published 0.0.5 contract) still requires one.
          let entry_moon_pkg = "\{@cli.entry_package_dir(project)}/moon.pkg"
          let generated_ok = if @fs.exists(entry_moon_pkg) {
            if @cli.entry_is_executable_package(read_text_file(entry_moon_pkg)) {
              println(
                "FAIL: host \"folotoy-ai-passport\" requires a \"deviceEntry\" package in passport.toml",
              )
              false
            } else {
              println(
                "ok: device entry generated from application entry \"\{project.contract.entry}\" at build time",
              )
              true
            }
          } else {
            println(
              "FAIL: entry package \"\{project.contract.entry}\" has no moon.pkg (\{entry_moon_pkg})",
            )
            false
          }
          if generated_ok {
            doctor_device_common(project, failures)
          } else {
            failures.push("device entry")
          }
        }
      }
    None => ()
  }
  if failures.length() > 0 {
    @cli.fail_cli("doctor found \{failures.length()} failing check(s)")
  }
  println("doctor: all checks passed")
}

///|
async fn verify_bsp_checkout(
  path : String,
  manifest : String,
  origin : String,
  failures : Array[String],
) -> Unit {
  match verify_sha256_manifest(manifest, "\{path}/components/bsp") {
    None =>
      println(
        "ok: FoloToy dependency (\{origin}) matches the pinned manifest at \{path}",
      )
    Some(problem) => {
      println(
        "FAIL: the FoloToy checkout at \{path} does not match \{manifest}: \{problem}",
      )
      failures.push("FoloToy dependency manifest")
    }
  }
}

///|
/// Side-effect free report on the external FoloToy dependency: which
/// checkout a build would use (project-provided or CLI-managed), whether it
/// matches the pinned manifest, and — when neither exists — where the
/// device build will clone the pinned revision. Doctor never downloads.
async fn report_bsp_dependency(
  project : @cli.Project,
  sdk_host : String,
  failures : Array[String],
) -> Unit {
  let manifest = "\{sdk_host}/bsp.sha256"
  let declared = match
    @cli.host_dependency_path(project.contract, "folotoy-ai-passport") {
    Some(rel) => Some(@cli.under_root(project.root, rel))
    None => None
  }
  let managed_dir = managed_bsp_dir(project)
  match
    plan_bsp_resolution(
      declared,
      match declared {
        Some(path) => @fs.exists("\{path}/components/bsp/include")
        None => false
      },
      managed_dir,
      @fs.exists("\{managed_dir}/components/bsp/include"),
    ) {
    ProjectProvided(path) =>
      verify_bsp_checkout(path, manifest, "project-provided", failures)
    ManagedReady(path) =>
      verify_bsp_checkout(path, manifest, "CLI-managed", failures)
    DeclaredMissing(path) => {
      println(
        "FAIL: passport.toml declares hostDependencies[\"folotoy-ai-passport\"] but no checkout exists at \{path}; fix the path, or remove the field to let the CLI manage the dependency",
      )
      failures.push("FoloToy dependency")
    }
    MaterializeManaged(path) =>
      println(
        "ok: FoloToy dependency not present yet; the device build clones \{BSP_COMMIT} into \{path}",
      )
  }
}

///|
/// Device checks that need a loaded contract with a device entry.
async fn doctor_device_project(
  project : @cli.Project,
  device_entry : String,
  failures : Array[String],
) -> Unit {
  println("ok: deviceEntry \"\{device_entry}\" declared")
  let entry_dir = @cli.device_entry_package_dir(project, device_entry)
  if @fs.exists("\{entry_dir}/moon.pkg") {
    println(
      "ok: device entry package \"\{device_entry}\" found under the module source root",
    )
  } else {
    println(
      "FAIL: device entry package \"\{device_entry}\" has no moon.pkg (\{entry_dir})",
    )
    failures.push("device entry package")
  }
  doctor_device_common(project, failures)
}

///|
/// Device checks shared by the declared-entry and generated-entry contracts:
/// sound resources, SDK device Host assets, and the external FoloToy
/// dependency.
async fn doctor_device_common(
  project : @cli.Project,
  failures : Array[String],
) -> Unit {
  doctor_sound_resources(project, failures)
  let mut host_dir : String? = None
  try {
    host_dir = Some(
      resolve_sdk_host_dir(
        project,
        HOST_DIR_FOLOTOY,
        @cli.sdk_device_host_files(),
      ),
    )
  } catch {
    @cli.Fail(message) => {
      println("FAIL: \{message}")
      failures.push("SDK device Host assets")
    }
    _ => {
      println(
        "FAIL: unexpected error while locating the SDK device Host assets",
      )
      failures.push("SDK device Host assets")
    }
  }
  match host_dir {
    Some(dir) => {
      println("ok: SDK device Host assets at \{dir}")
      report_bsp_dependency(project, dir, failures)
    }
    None => ()
  }
}
