///|
/// The registry is deterministic data: the CLI's `passport hosts` output and
/// every descriptor-driven decision depend on these invariants.

///|
test "registry lists exactly the registered hosts in stable order" {
  let a = @hosts.all_hosts()
  let b = @hosts.all_hosts()
  inspect(a.length(), content="2")
  inspect(a[0].id, content="web")
  inspect(a[1].id, content="folotoy-ai-passport")
  // Repeated calls return identical, independently-ordered data.
  inspect(
    a.map(fn(d) { d.id }).join(","),
    content=b.map(fn(d) { d.id }).join(","),
  )
}

///|
test "find_host matches exact ids only and returns None for unknown hosts" {
  inspect(@hosts.find_host("web") is Some(_), content="true")
  inspect(@hosts.find_host("folotoy-ai-passport") is Some(_), content="true")
  inspect(@hosts.find_host("Web") is Some(_), content="false")
  inspect(@hosts.find_host("zectrix-note4") is Some(_), content="false")
  inspect(@hosts.find_host("") is Some(_), content="false")
}

///|
test "web host does not overclaim capabilities" {
  let web = @hosts.find_host("web").unwrap()
  let exposed = web.capabilities.sdk_exposed
  // Exposed today: presentation, input, PCM output/input, battery fixture, timing.
  inspect(exposed.contains(@hosts.Display), content="true")
  inspect(exposed.contains(@hosts.Input), content="true")
  inspect(exposed.contains(@hosts.AudioOutput), content="true")
  inspect(exposed.contains(@hosts.Battery), content="true")
  inspect(exposed.contains(@hosts.Clock), content="true")
  inspect(exposed.contains(@hosts.Power), content="true")
  inspect(exposed.contains(@hosts.AudioInput), content="true")
  // No network is exposed.
  inspect(exposed.contains(@hosts.Network), content="false")
  // And the browser runtime has no battery gauge: the hardware plane must
  // not claim one either.
  inspect(
    web.capabilities.hardware_known.contains(@hosts.Battery),
    content="false",
  )
  inspect(web.backend is @hosts.Implemented, content="true")
}

///|
test "folotoy host registers the microphone and the implemented device backend" {
  let f = @hosts.find_host("folotoy-ai-passport").unwrap()
  // Factual hardware, including the microphone.
  inspect(
    f.capabilities.hardware_known.contains(@hosts.AudioInput),
    content="true",
  )
  inspect(
    f.capabilities.hardware_known.contains(@hosts.AudioOutput),
    content="true",
  )
  inspect(
    f.capabilities.hardware_known.contains(@hosts.Display),
    content="true",
  )
  inspect(f.capabilities.hardware_known.contains(@hosts.Input), content="true")
  inspect(
    f.capabilities.hardware_known.contains(@hosts.Battery),
    content="true",
  )
  inspect(
    f.capabilities.hardware_known.contains(@hosts.Network),
    content="true",
  )
  inspect(f.capabilities.hardware_known.contains(@hosts.Clock), content="true")
  // The implemented device backend exposes the same SDK application
  // capabilities as the web Host — no more, no less.
  inspect(f.capabilities.sdk_exposed.contains(@hosts.Display), content="true")
  inspect(f.capabilities.sdk_exposed.contains(@hosts.Input), content="true")
  inspect(
    f.capabilities.sdk_exposed.contains(@hosts.AudioOutput),
    content="true",
  )
  inspect(f.capabilities.sdk_exposed.contains(@hosts.Battery), content="true")
  inspect(f.capabilities.sdk_exposed.contains(@hosts.Clock), content="true")
  inspect(f.capabilities.sdk_exposed.contains(@hosts.Power), content="true")
  inspect(
    f.capabilities.sdk_exposed.contains(@hosts.AudioInput),
    content="true",
  )
  inspect(f.capabilities.sdk_exposed.contains(@hosts.Network), content="false")
  inspect(f.backend is @hosts.Implemented, content="true")
}

///|
test "capability labels are the stable lowercase CLI vocabulary" {
  inspect(@hosts.Display.to_label(), content="display")
  inspect(@hosts.Input.to_label(), content="input")
  inspect(@hosts.AudioOutput.to_label(), content="audio_output")
  inspect(@hosts.AudioInput.to_label(), content="audio_input")
  inspect(@hosts.Battery.to_label(), content="battery")
  inspect(@hosts.Network.to_label(), content="network")
  inspect(@hosts.Clock.to_label(), content="clock")
  inspect(@hosts.Power.to_label(), content="power")
  inspect(
    @hosts.render_capabilities([@hosts.Display, @hosts.AudioInput, @hosts.Clock]),
    content="display, audio_input, clock",
  )
}

///|
fn mentions_wiring(text : String) -> Bool {
  let lower = text.to_lower()
  lower.contains("gpio") ||
  lower.contains("i2s") ||
  lower.contains("i2c") ||
  lower.contains("spi")
}

///|
test "descriptors carry facts but no wiring-level configuration" {
  for descriptor in @hosts.all_hosts() {
    // Facts exist and none of them leaks pin/bus-level configuration tokens.
    inspect(descriptor.facts.length() > 0, content="true")
    for fact in descriptor.facts {
      inspect(mentions_wiring(fact), content="false")
    }
  }
}
