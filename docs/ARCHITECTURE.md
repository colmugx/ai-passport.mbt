# Architecture

The module `colmugx/ai-passport` is a reusable Mooncakes SDK with seven packages under `src/`. Applications depend on semantic SDK contracts. A host or device backend supplies the same `Clock`, `DisplaySink`, `PcmSink`, and `BatterySource` behavior through replaceable adapters. No platform library belongs in an application-facing package.

```text
Application logic
  ├─ core: 120×160 logical dimensions, Color and geometry
  ├─ graphics: Canvas → read-only FrameView → driver.DisplaySink
  ├─ input: Up / Down / Ok and InputState
  ├─ music: immutable Song → Sequencer + TickClock
  ├─ audio: Player → Synth → signed PCM16 → audio.PcmSink
  └─ battery: cached Battery → BatterySource
```

`Canvas` stores canonical RGB565 pixels in a private `FixedArray[UInt16]`. `FrameView` shares that storage, exposes dimensions and row copies, and is consumed synchronously before the canvas mutates. Presentation details stay behind `DisplaySink`.

`Player` is the authoritative audio sample clock. It advances `TickClock` at sample boundaries, drives the sequencer's preallocated event path, triggers up to four monophonic synth voices, and reports elapsed dotted-quarter beats across loop wraps. A backend feeds the actual sample count to `Player::render`; frame pacing does not advance music time. A song is a deep-copied authoring snapshot, so sequencer and player capacities stay stable.

The native and JS targets are supported and tested. Forest Walk recovery from git history, browser/device integration, and Mooncakes release tagging belong to the separate template/release work, not this SDK repository. QEMU or hardware emulation is outside scope.
