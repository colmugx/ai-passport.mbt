///|
/// Filesystem side of project loading (the pure contract parsing lives in
/// `src/cli`).

///|
async fn read_text_file(path : String) -> String {
  @fs.read_file(path).text() catch {
    _ => @cli.fail_cli("cannot read \{path}")
  }
}

///|
/// Loads and validates the project at `project_dir` (absolute or relative to
/// the current directory).
async fn load_project(project_dir : String) -> @cli.Project {
  let cwd = match @env.current_dir() {
    Some(dir) => dir
    None => "."
  }
  let joined = if project_dir.has_prefix("/") {
    project_dir
  } else if project_dir == "." {
    cwd
  } else {
    "\{cwd}/\{project_dir}"
  }
  let root = @fs.realpath(joined) catch {
    _ => @cli.fail_cli("project directory \"\{project_dir}\" is not accessible")
  }
  guard @fs.exists("\{root}/moon.mod") else {
    @cli.fail_cli(
      "\{project_dir} is not an application project (no moon.mod at the root)",
    )
  }
  let mod_text = read_text_file("\{root}/moon.mod")
  let module_name = match @cli.moon_mod_scalar(mod_text, "name") {
    Some(name) => name
    None => @cli.fail_cli("moon.mod does not declare a module name")
  }
  let source_dir = match @cli.moon_mod_scalar(mod_text, "source") {
    Some(dir) => dir
    None => ""
  }
  let contract_path = "\{root}/passport.json"
  guard @fs.exists(contract_path) else {
    @cli.fail_cli(
      "no passport.json at the project root (\{project_dir}); the project contract declares the application entry and assets",
    )
  }
  let contract = @cli.parse_contract(read_text_file(contract_path))
  { root, module_name, source_dir, contract, }
}
