# Architecture

The module `colmugx/ai-passport` is a MoonBit application SDK and its co-versioned Host toolchain. Applications depend on semantic SDK contracts; a Host supplies those semantics through replaceable adapters and owns the platform-specific build/runtime/deployment integration for one explicitly supported execution environment. Host is the only backend abstraction exposed by the project.

```text
Application logic
  ├─ core: 120×160 logical dimensions, Color and geometry
  ├─ graphics: Canvas → read-only FrameView → driver.DisplaySink
  ├─ input: Up / Down / Ok and InputState
  ├─ music: immutable Song → Sequencer + TickClock
  ├─ audio: Player → Synth → signed PCM16 → audio.PcmSink
  └─ battery: cached Battery → BatterySource

                    semantic SDK contracts
                              │
                 ┌────────────┴────────────┐
                 │                         │
              Host: web          Host: folotoy-ai-passport
              runtime +          runtime/build/flash backend
              bundle tooling     (ESP-IDF device build)
```

`Canvas` stores canonical RGB565 pixels in a private `FixedArray[UInt16]`. `FrameView` shares that storage, exposes dimensions and row copies, and is consumed synchronously before the canvas mutates. Presentation details stay behind `DisplaySink`.

`Player` is the authoritative audio sample clock. It advances `TickClock` at sample boundaries, drives the sequencer's preallocated event path, triggers up to four monophonic synth voices, and reports elapsed dotted-quarter beats across loop wraps. A backend feeds the actual sample count to `Player::render`; frame pacing does not advance music time. A song is a deep-copied authoring snapshot, so sequencer and player capacities stay stable.

Since R4A1 the module also ships the tooling that turns an application into a runnable Host bundle: `src/hosts` is the Host registry, `src/cli` holds project/Host-independent CLI logic, and `src/cmd/passport` is the `passport` executable. The Web Host implementation and browser assets remain under `hosts/web`; the FoloToy physical Host's ESP-IDF glue and flash tooling live under `hosts/folotoy/ai-passport` (its BSP is an external pinned dependency) and are materialized into a per-project build workspace by the CLI. A physical Host owns ESP-IDF/BSP/flashing details under its Host implementation; those details are not application APIs and are not copied into downstream application projects (the CLI copies host implementation files only into the generated device workspace, never into project sources).

Forest Walk and other applications belong downstream. They are integration/reference applications for this SDK, never CLI or Host semantics. The Web Host and physical Hosts must execute the same compiled MoonBit application semantics rather than maintaining parallel implementations.

Native, JS, and wasm targets are tested where supported by the relevant packages. QEMU/hardware emulation is outside the current scope; real device acceptance remains a separate evidence tier from source/CI validation.
