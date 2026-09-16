///|
/// `passport hosts`: the deterministic registry listing. Ordering and text
/// are part of the CLI contract and pinned by tests (see `src/cli`).

///|
fn hosts_command() -> Unit {
  for descriptor in @hosts.all_hosts() {
    println(@cli.render_host(descriptor))
  }
}
