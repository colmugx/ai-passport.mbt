# ai-passport.mbt

MoonBit application SDK and co-versioned Host toolchain. The first physical Host is the [FoloToy AI Passport](https://github.com/FoloToy/ai-passport); additional Hosts are added only when this project explicitly implements and validates them.

Mooncakes module: `colmugx/ai-passport`.

The SDK defines portable MoonBit application contracts. **Host is the only backend abstraction**: each Host owns the platform-specific runtime/build/deployment integration needed to implement the same application semantics. Native, JS, and wasm are tested where supported by the relevant packages.

## Repository scope

This repository owns both reusable SDK code and the tooling/runtime assets for registered Hosts. It does **not** own application semantics or starter applications: Forest Walk and other reference apps belong in downstream application repositories.

Platform details such as browser APIs, ESP-IDF, BSPs, GPIO, buses, codecs, and flashing may exist inside a Host implementation when required, but they must stay behind the Host boundary and out of public application APIs. The Web Host browser code lives in `hosts/web/*.js`; the FoloToy physical Host backend builds real firmware through the `passport` CLI (no flashing is ever performed by the SDK or CI).

## Packages

| Package | Contents |
| --- | --- |
| `core` | `Point`, `Size`, `Rect`, `Color` (RGB565 conversion), `LOGICAL_WIDTH = 120`, `LOGICAL_HEIGHT = 160` |
| `graphics` | `Canvas` drawing (`clear`, `pixel`, `line`, `rect`, `fill_rect`, `sprite`, bitmap text), `SpriteSheet`, text metrics, read-only `FrameView` |
| `input` | Semantic `Button` (`Up` / `Down` / `Ok`), `ButtonEvent` (`Press` / `Click` / `DoubleClick` / `LongPress`), edge-detecting `InputState` |
| `music` | `Meter` (6/8), `Tempo` (dotted-quarter BPM), `Pitch` / `Note` / `Track` / `Song` (max four tracks), `Sequencer`, `TickClock` |
| `audio` | 16 kHz PCM16 mono `Synth` with four monophonic voices, five waveforms (`Pulse12`, `Pulse25`, `Pulse50`, `Triangle`, `Noise`), and a sample-accurate `Player` that owns the music transport (loop, pause/resume, beat sync) |
| `battery` | `BatterySource` trait and caching `Battery`; readings are `Int?` so unavailable values are explicit |
| `driver` | Backend-facing `Clock` and `DisplaySink` contracts, plus test fixtures (`ZeroClock`, `SinkProbe`) |
| `hostabi` | Internal, experimental wasm host-boundary package: ABI v0 constants, the closure-injected `HostBridge` (`DisplaySink` / `PcmSink` / `BatterySource` / `Clock` adapters), wasm-gated `passport.*` externs, and inline-WAT `u16` store/load helpers |

## Display model

The logical screen is fixed at **120×160** pixels for v0.1. Applications draw with logical coordinates; the backend scales/presents however the hardware requires. Colors are authored as RGB and quantized to **RGB565** by `Color::to_rgb565()` — the same quantized colors a preview and the device LCD show.

`Canvas` stores one `UInt16` RGB565 value per pixel. `Canvas::frame_view()` creates a read-only view sharing that storage; it does not copy a full frame. `FrameView::width()`, `height()`, and `copy_rgb565_row(y~, out~ : FixedArray[Int]) -> Int` let a backend read rows. The copy returns the number of pixels written: zero for an invalid row and a prefix count when `out` is too short. A view is valid only until its canvas is next mutated, so a display sink must consume it synchronously or copy the rows it needs. Graphics public APIs do not expose strip rendering or display-controller specifics.

## Input model

Buttons are semantic values — `Up`, `Down`, `Ok` — never GPIO or ADC channels. `InputState` turns raw press/release feeds into `pressed`, `just_pressed`, and `just_released` edges per frame via `advance()`.

## Music and audio

- 6/8 meter with dotted-quarter BPM tempo (default 76). Song time is measured in ticks, with four ticks per eighth note by default and twelve ticks per dotted-quarter beat.
- `Song::new` accepts at most four tracks (raising `SongError::TooManyVoices` for more) and stores an **immutable snapshot**: the caller's authoring arrays are deep-copied, so mutating them afterwards cannot change a constructed song. Read access: `meter()`, `tempo()`, `ticks_per_eighth()`, `track_count()`.
- `Sequencer` walks a song with deterministic looping (arrival-based: the first step fires the tick-0 note starts); `length()` is the loop length in song ticks. `TickClock` converts elapsed samples into song ticks with exact integer accumulation (no drift), and `ticks_to_samples_exact` measures from the current clock phase to a future tick boundary.
- `Synth` renders 16 kHz signed PCM16 mono, mixes up to four monophonic voices, and clamps to `[-32768, 32767]`. Instrument articulation defines envelope, volume, and optional vibrato; the waveform defines oscillator shape. Integer envelope ramps reach their targets at the configured sample duration, including release from the level where it begins.
- `Player` owns the authoritative sample clock and transport. It fires tick-0 notes before the first sample, processes later starts at exact sample boundaries, and uses a preallocated event buffer through `Sequencer::step_into`. Note gates end on their musical tick boundary despite fractional clock carry. `beat()` counts elapsed dotted-quarter beats across loops, including one-tick loops, and pause freezes that count.

## Battery

`BatterySource::percent` and `millivolts` return `Int?` to represent unavailable readings. `Battery` caches readings behind an explicit `refresh()`; construction performs no source I/O. `Battery::fixture(percent~)` supplies a test value.

## Driver contracts (for Host authors)

A Host implements the relevant `pub(open)` traits:

- `Clock` — `monotonic_ms()` and `sleep_ms()` for frame pacing.
- `DisplaySink` — `present(frame~ : @graphics.FrameView)` receives a synchronous, read-only view of the finished RGB565 canvas.
- `PcmSink` (in `audio`) — `write(samples~ : FixedArray[Int])` receives signed PCM16 mono sample blocks.
- `BatterySource` (in `battery`) — `percent()` and `millivolts()` return optional readings.

Host glue stays behind the Host boundary; reusable application semantics remain MoonBit SDK/application code.

## Web host (wasm backend)

The SDK ships an application-agnostic web host backend for compiled MoonBit `wasm` apps: `hosts/web/passport-host.js` with `hosts/web/pcm-worklet.js` and `hosts/web/index.html` implements the internal, experimental ABI v0 contract specified in `docs/WEB_HOST.md`. It is a host **backend**, not an application preview or template — it holds no application state, and all browser code lives in the `hosts/web/*.js` assets, not in SDK MoonBit packages. `src/hostabi` adapts the SDK contracts to the raw wasm boundary, and `src/fixture` is the smallest main package that proves the boundary end-to-end with deterministic pixels and PCM. ABI v0 is internal and not a frozen public SDK API; the bundle contract is `<bundle>/app.wasm` plus `<bundle>/assets/` (`hosts/web/README.md`).

Verify the boundary with the fixture and integration suite, from the repository root:

```sh
moon build --target wasm --release      # fixture app.wasm, release profile
moon build --target wasm                # fixture app.wasm, debug profile (the suite pins both)
node hosts/web/tools/gen-test-pcm.mjs   # once; creates the committed PCM asset
node hosts/web/tools/make-bundle.mjs    # assembles _build/passport-bundle
node hosts/web/test/run-tests.mjs       # 28 suites; exits 2 if the fixture artifacts are missing
```

CI runs the same gate in a dedicated `wasm-host` job (`.github/workflows/ci.yml`): `moon check` and `moon test` with `--target wasm`, both fixture build profiles, `passport hosts` / `passport doctor` smoke runs, the package-list proof, and the full integration suite — including the real-browser suites and the passport-CLI fixture suites through pinned playwright chromium — with no skip flags.

## Passport CLI

The module ships the `passport` CLI: build and serve applications for registered Hosts, with **Host as the only backend abstraction**. Registered Hosts: `web` (implemented) and `folotoy-ai-passport` (implemented; ESP-IDF device build, no flash). A downstream project is any MoonBit module with a `passport.toml` at its root declaring ONE application entry — the same application package serves every Host:

```toml
entry = "app"
```

The entry path is relative to the module source root: with the normal `source = "src"` in `moon.mod`, the application lives at `src/app` and nothing about the project's imports changes. The application package implements the `Application` contract (`colmugx/ai-passport/application`) and exposes `pub fn passport_main() -> &Application`; the CLI generates the Host entry adapters under the source root's `passport-generated/` tree (build output — gitignore `passport-generated/`). See `docs/PASSPORT_CLI.md`.

```sh
moon run --target wasm src/cmd/passport hosts
moon run --target wasm src/cmd/passport build --host web --project <app-dir>
moon run --target wasm src/cmd/passport build --host folotoy-ai-passport --project <app-dir>
moon run --target wasm src/cmd/passport dev --host web --project <app-dir>
```

## Development

Run `moon check --target native --output-json` and `moon test --target native --output-json`, then the same checks with `--target js`. Run `moon info` to regenerate public interfaces and `moon fmt` to format MoonBit files. Review generated interface changes before release.
