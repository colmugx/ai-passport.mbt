///|
/// Deterministic Host rendering for the CLI (snapshot-tested) and the Host
/// validation helpers.

///|
/// Renders one Host descriptor deterministically. Ordering and text are part
/// of the CLI contract.
pub fn render_host(descriptor : @hosts.HostDescriptor) -> String {
  let out = StringBuilder()
  out.write_string(descriptor.id)
  out.write_string("\n")
  out.write_string("  \{descriptor.summary}\n")
  out.write_string(
    "  capabilities sdk-exposed: \{render_capabilities_or_none(descriptor.capabilities.sdk_exposed)}\n",
  )
  out.write_string(
    "  capabilities hardware-known: \{render_capabilities_or_none(descriptor.capabilities.hardware_known)}\n",
  )
  for fact in descriptor.facts {
    out.write_string("  fact: \{fact}\n")
  }
  match descriptor.backend {
    @hosts.Implemented => out.write_string("  backend: implemented\n")
    @hosts.NotMigrated(reason) => out.write_string("  backend: \{reason}\n")
  }
  out.to_string()
}

///|
fn render_capabilities_or_none(caps : Array[@hosts.Capability]) -> String {
  if caps.length() == 0 {
    "(none)"
  } else {
    @hosts.render_capabilities(caps)
  }
}

///|
/// Renders the exact registered host id list used in error messages.
pub fn known_host_ids() -> String {
  @hosts.all_hosts().map(fn(d) { d.id }).join(", ")
}

///|
/// Validates a Host id against the registry. Unknown ids fail with the known
/// list; unimplemented backends fail with their declared boundary.
pub fn require_implemented_host(
  host_id : String,
) -> @hosts.HostDescriptor raise {
  let descriptor = match @hosts.find_host(host_id) {
    Some(d) => d
    None =>
      fail_cli(
        "unknown host \"\{host_id}\" (registered hosts: \{known_host_ids()})",
      )
  }
  match descriptor.backend {
    @hosts.Implemented => descriptor
    @hosts.NotMigrated(reason) =>
      fail_cli(
        "host \"\{host_id}\" \{reason} (this release implements the web backend only)",
      )
  }
}

///|
/// Validates a Host id without requiring an implemented backend (used by
/// doctor to diagnose registered-but-unimplemented Hosts).
pub fn require_known_host(host_id : String) -> @hosts.HostDescriptor raise {
  match @hosts.find_host(host_id) {
    Some(d) => d
    None =>
      fail_cli(
        "unknown host \"\{host_id}\" (registered hosts: \{known_host_ids()})",
      )
  }
}
