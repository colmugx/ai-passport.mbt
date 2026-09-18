///|
/// Pure boundary tests for the project paths that may later feed generated
/// output and recursive deletion.
test "module source accepts only portable project-relative paths" {
  for source in ["", "src", "src/app"] {
    try validate_module_source_dir(source) catch {
      _ => fail("expected safe source path to pass")
    } noraise {
      _ => ()
    }
  }
  for
    source in [
      "/tmp/app", "../outside", "src/../outside", "./src", "src//app", "src\\app",
    ] {
    try validate_module_source_dir(source) catch {
      @cli.Fail(_) => ()
      _ => fail("expected CliError")
    } noraise {
      _ => fail("expected unsafe source path to fail")
    }
  }
}

///|
test "canonical containment respects path-component boundaries" {
  inspect(path_is_within("/work/app", "/work/app"), content="true")
  inspect(path_is_within("/work/app", "/work/app/src"), content="true")
  inspect(path_is_within("/work/app", "/work/app/src/main"), content="true")
  inspect(path_is_within("/work/app", "/work/app-evil"), content="false")
  inspect(path_is_within("/work/app", "/work/other"), content="false")
}
