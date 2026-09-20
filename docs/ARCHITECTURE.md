# Architecture

The module `colmugx/ai-passport` is a MoonBit application SDK and its co-versioned Host toolchain. Applications depend on semantic SDK contracts; a Host supplies those semantics through replaceable adapters and owns the platform-specific build/runtime/deployment integration for one explicitly supported execution environment. Host is the only backend abstraction exposed by the project.

```text
Application logic
  ├─ core: 120×160 logical dimensions, Color and geometry
  ├─ graphics: Canvas → read-only FrameView → driver.DisplaySink
  ├─ input: Up / Down / Ok and InputState
  ├─ audio: Sound → Playback controls → internal Host sound runtime
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

The core SDK does not own audio composition, synthesis, sequencing, or codecs. Its public resource API separates generated `Sound` values from opaque `Playback` instances: playing the same sound twice creates independently controlled playbacks, capacity exhaustion returns `None`, and loop behavior belongs to the play call. A narrow internal operation table carries only sound IDs, playback handles and positions to the Host; it is not a public PCM sink, mixer graph, or middleware API.

Sound resources have one build-time source of truth. `passport.toml` declares ordered `[[sounds]]` entries; the filesystem-free metadata compiler validates names and sources, assigns declaration-order IDs, and derives MoonBit symbols. An application-owned package invokes `passport generate-sounds $input $output` through Moon `rule` / `dev_build` to produce its typed enum and is conventionally imported as `@sounds`; its package name is not fixed. Web and device builds call the same metadata compiler, additionally validate PCM bytes, and serialize the APSB v1 bank. Both Host runtimes validate and consume those same bank bytes, then mix their fixed playback slots internally before applying application-wide master volume and mute.

The module also ships the tooling that turns an application into a runnable Host bundle: `src/hosts` is the Host registry, `src/cli` holds project/Host-independent CLI logic, and `src/cmd/passport` is the `passport` executable. The Web Host implementation and browser assets remain under `hosts/web`; the FoloToy physical Host's ESP-IDF glue and flash tooling live under `hosts/folotoy/ai-passport` (its BSP is an external pinned dependency) and are materialized into a per-project build workspace by the CLI. A physical Host owns ESP-IDF/BSP/flashing details under its Host implementation; those details are not application APIs and are not copied into downstream application projects (the CLI copies host implementation files only into the generated device workspace, never into project sources).

Forest Walk and other applications belong downstream. They are integration/reference applications for this SDK, never CLI or Host semantics. The Web Host and physical Hosts must execute the same compiled MoonBit application semantics rather than maintaining parallel implementations.

Native, JS, and wasm targets are tested where supported by the relevant packages. QEMU/hardware emulation is outside the current scope; real device acceptance remains a separate evidence tier from source/CI validation.
