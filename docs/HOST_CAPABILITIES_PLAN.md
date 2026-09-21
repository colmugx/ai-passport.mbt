# Host capabilities implementation plan and tracking

## Status overview

| Phase | Scope | Owner | Status |
| --- | --- | --- | --- |
| 0 | Reconnaissance and baseline | Primary agent; read-only Luna worker | Complete |
| 1 | Complete button events and conflict handling | Primary agent | Complete (`333cea2`) |
| 2 | Microphone input and audio channel contract | Primary agent | Complete |
| 3 | Display capability, backlight, and panel presentation | Primary agent | Complete, pending commit |
| 4 | Sleep and wake contract | Primary agent | Pending |
| 5 | Documentation, full gates, commits, and one PR | Primary agent | Pending |

## Scope declaration

This round implements portable application-facing capabilities across the Web and FoloToy Hosts. Hardware-specific pins, buses, codecs, and wake mechanisms remain inside Hosts. LVGL is evaluated against the existing SDK drawing path; it is not automatically included in firmware. Physical-device behavior must be reported separately from software build and test evidence.

## File ownership

The primary agent owns all production code, tests, documentation, commits, and PR work. The Luna worker is restricted to read-only exploration. No parallel production edits are permitted.

## Task details

### Button events

- Preserve semantic `Up`, `Down`, `Ok` and expose press, click, double click, and long press behavior to applications.
- Specify duplicate, overlapping, and simultaneous-button behavior, including the ADC-ladder limitation on FoloToy hardware.
- Test the shared semantics and both Host delivery paths.

### Audio input

- Add a portable microphone contract with explicit availability, lifecycle, format, and failure reporting.
- Implement Web and FoloToy transports without moving device codec details into application APIs.
- Cover startup, recording, stop, capacity, and error paths.

### Display and light

- Add an optional illumination capability so displays without a light remain valid Hosts.
- Preserve a clear rendering contract for RGB565 and future monochrome presentation.
- Make application-visible dimensions queryable and render FoloToy at its full 240×320 panel resolution. Keep pixel encoding and presentation conversion behind Host contracts so a future monochrome Host can consume the same application drawing semantics.

### Power

- Define application-requested sleep, wake cause, and unsupported behavior.
- Implement Host behavior and test state transitions; record physical-device validation limits.

### Closeout

- Update `AGENTS.md` and architecture documentation for changed contracts.
- Run all supported-target MoonBit gates, Web real-browser integration, FoloToy Host tests and available firmware build gate.
- Make separate feature commits, then submit one PR.

## Work log

- 2026-09-21: Started from clean `main`; created `feature/host-input-audio-display-power`.
- 2026-09-21: Baseline passed: wasm 263/263, native 267/267, JS 252/252, FoloToy Python 16/16. Checks passed for wasm, native, and JS.
- 2026-09-21: `gh auth status` reports an invalid GitHub token; PR publishing will be retried after implementation with available credentials or browser session.
- 2026-09-21: User directed that the primary agent personally implements all code; Luna worker may only perform read-only exploration.
- 2026-09-21: User chose explicit application sleep requests with wake-cause reporting.
- 2026-09-21: User chose queryable display dimensions and full-resolution 240×320 FoloToy rendering in this round.
- 2026-09-21: Button events committed as `333cea2`; the shared ADC ladder cannot disambiguate physical button chords, while Web buttons are independent.
- 2026-09-21: Added explicit PCM16 capture lifecycle on both Hosts, bounded queues with drop telemetry, and full-duplex Web tests. Native, JS, Wasm MoonBit suites and real-browser Web integration passed. Physical microphone behavior remains unverified without a device.
- 2026-09-21: Audio input committed as `abf2d27`. Display now reports active Host size and optional light; Web and FoloToy use full 240×320. RGB565 drawing remains semantic for future monochrome Host quantization. Three-target MoonBit suites and real-browser Web integration passed. Physical RAM and LCD performance require device validation.

## Open Questions

- None pending from the user. Detailed threshold and transport policy are implementation decisions to be recorded before code changes.
