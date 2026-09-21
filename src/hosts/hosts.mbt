///|
/// The Host model: a Host is one explicitly supported and validated
/// execution environment for an AI Passport application (for example the
/// browser Web Host or the FoloToy AI Passport wearable). The Host is the
/// ONLY backend abstraction this SDK exposes: backend selection in the
/// public surface always names a Host, and no other backend vocabulary
/// exists.

///|
/// Semantic capabilities a Host may provide. Capabilities never describe
/// hardware wiring (pins, buses, controllers) — only what an application can
/// perceive.
pub(all) enum Capability {
  /// Framebuffer presentation through the SDK display contract.
  Display
  /// Semantic Up / Down / Ok input.
  Input
  /// Audio playback output.
  AudioOutput
  /// Audio capture input (microphone).
  AudioInput
  /// Battery information.
  Battery
  /// Network connectivity (for example Wi-Fi or Bluetooth LE).
  Network
  /// Timers / a monotonic clock.
  Clock
} derive(Eq, Debug)

///|
/// Explicitly promotes the derived `Eq` methods to regular methods.
pub extend Capability with Eq::{not_equal, equal}

///|
/// Explicitly promotes the derived `Debug` method to a regular method.
pub extend Capability with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Stable lowercase label for a capability (used by the CLI output and
/// snapshot tests; part of the user-facing vocabulary).
pub fn Capability::to_label(self : Capability) -> String {
  match self {
    Display => "display"
    Input => "input"
    AudioOutput => "audio_output"
    AudioInput => "audio_input"
    Battery => "battery"
    Network => "network"
    Clock => "clock"
  }
}

///|
/// The two capability planes of a Host are kept separate on purpose: hardware
/// that is factually present does not imply an SDK application API exists for
/// it, and nothing may be claimed as SDK-exposed unless a public SDK contract
/// actually reaches it today.
pub(all) struct HostCapabilities {
  /// Capabilities reachable today through public SDK application APIs.
  sdk_exposed : Array[Capability]
  /// Capabilities confirmed on the Host's real hardware or runtime
  /// environment, whether or not the SDK exposes them yet.
  hardware_known : Array[Capability]
} derive(Debug)

///|
/// Explicitly promotes the derived `Debug` method to a regular method.
pub extend HostCapabilities with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Stable, deterministic rendering: labels joined with ", " in the descriptor
/// declaration order.
pub fn render_capabilities(caps : Array[Capability]) -> String {
  caps.map(fn(c) { c.to_label() }).join(", ")
}

///|
/// How far the SDK tooling supports one Host today. A Host may be registered
/// and described before its build backend is migrated; the CLI reports the
/// boundary explicitly instead of pretending the operation exists.
pub(all) enum BackendStatus {
  /// The SDK CLI can build and run applications for this Host.
  Implemented
  /// No build/dev backend is migrated yet; the payload explains the boundary.
  NotMigrated(String)
} derive(Eq, Debug)

///|
/// Explicitly promotes the derived `Eq` methods to regular methods.
pub extend BackendStatus with Eq::{not_equal, equal}

///|
/// Explicitly promotes the derived `Debug` method to a regular method.
pub extend BackendStatus with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Descriptor for one registered Host: its identity, its capabilities on the
/// two planes, factual notes, and its tooling status. Descriptors are
/// deterministic data — the same release always renders them identically.
pub(all) struct HostDescriptor {
  /// Exact Host identifier used on the CLI (for example `web`).
  id : String
  /// One-line human summary.
  summary : String
  capabilities : HostCapabilities
  /// Factual hardware/backend notes. Descriptive only: never wiring-level
  /// configuration data (no pin numbers, no bus maps).
  facts : Array[String]
  /// Tooling status of this Host's build/dev backend.
  backend : BackendStatus
} derive(Debug)

///|
/// Explicitly promotes the derived `Debug` method to a regular method.
pub extend HostDescriptor with @moonbitlang/core/debug.Debug::{to_repr}
