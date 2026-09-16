///|
/// Pure CLI support logic for the passport command-line tool: the project
/// contract, deterministic Host rendering, entry URL derivation and module
/// fact scanning. Free of filesystem and process access so it is testable on
/// every target; `src/cmd/passport` wires it to the outside world.

///|
/// CLI failure with a user-facing message.
pub(all) suberror CliError {
  Fail(String)
} derive(Eq, Debug)

///|
/// Fails the current operation with a user-facing message. Polymorphic in
/// the continuation type so it works in every match branch.
pub fn[T] fail_cli(message : String) -> T raise {
  raise Fail(message)
}
