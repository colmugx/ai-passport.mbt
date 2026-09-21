///|
/// The Host registry: every explicitly supported Host of this SDK release is
/// registered here exactly once, in a stable order. Future Hosts (for example
/// `zectrix-note4`) are added here without changing the CLI grammar.

///|
/// The Web Host: the SDK's own application-agnostic wasm host backend. An
/// application compiles to `app.wasm` (ABI v0) and runs in the browser from a
/// bundle assembled by the passport CLI (`passport build --host web`).
fn web_descriptor() -> HostDescriptor {
  {
    id: "web",
    summary: "Browser Web Host: the SDK wasm app in a browser over HTTP.",
    capabilities: {
      sdk_exposed: [Display, Input, AudioOutput, AudioInput, Battery, Clock],
      // The browser runtime really provides display, keyboard input, an
      // audio output device and clocks; it has no battery gauge, so Battery
      // is deliberately absent from the hardware plane (the exposed Battery
      // is a fixture/unavailable state, never a real reading).
      hardware_known: [Display, Input, AudioOutput, AudioInput, Clock],
    },
    facts: [
      "full-resolution 240x320 RGB565 presentation with virtual backlight", "semantic Up / Down / Ok input translated from the keyboard",
      "shared APSB sound-bank playback with independent handles", "per-playback position plus master volume and mute",
      "permission-gated microphone capture as PCM16 mono 16000 Hz", "battery is a fixture/unavailable state, not a real gauge",
      "frame pacing from the browser animation clock; monotonic now_us", "no network or persistent storage capability is exposed",
    ],
    backend: Implemented,
  }
}

///|
/// The FoloToy AI Passport wearable. Its ESP-IDF device build backend is
/// implemented: the SDK application capabilities exposed on the web Host are
/// also exposed here, over the physical hardware described factually below.
fn folotoy_descriptor() -> HostDescriptor {
  {
    id: "folotoy-ai-passport",
    summary: "FoloToy AI Passport wearable (ESP32-C3): the SDK app on the physical device.",
    capabilities: {
      sdk_exposed: [Display, Input, AudioOutput, AudioInput, Battery, Clock],
      hardware_known: [
        Display,
        Input,
        AudioOutput,
        AudioInput,
        Battery,
        Network,
        Clock,
      ],
    },
    facts: [
      "ESP32-C3, 8 MB flash, no PSRAM", "physical ST7789P3 240x320 RGB565 panel and adjustable backlight",
      "semantic Up / Down / Ok physical buttons", "audio playback output", "shared APSB sound-bank playback",
      "microphone capture as PCM16 mono 16000 Hz", "CW2017 battery gauge", "Wi-Fi and Bluetooth LE",
      "timers / monotonic clock",
    ],
    backend: Implemented,
  }
}

///|
/// All registered Hosts in stable, deterministic registry order. The order is
/// part of the CLI contract: `passport hosts` always lists Hosts exactly in
/// this sequence.
pub fn all_hosts() -> Array[HostDescriptor] {
  [web_descriptor(), folotoy_descriptor()]
}

///|
/// Looks up one Host by exact identifier. Unknown identifiers return `None`;
/// callers decide how to report them (the CLI fails with the known ids).
pub fn find_host(id : String) -> HostDescriptor? {
  for descriptor in all_hosts() {
    if descriptor.id == id {
      return Some(descriptor)
    }
  }
  None
}
