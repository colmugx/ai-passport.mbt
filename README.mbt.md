# ai-passport.mbt

Reusable MoonBit SDK for the [FoloToy AI Passport](https://github.com/FoloToy/ai-passport) wearable.

Mooncakes module: `colmugx/ai-passport`.

The SDK defines portable MoonBit application contracts. Host and device backends must implement the same semantics through thin platform adapters. Native and JS are supported and tested targets.

## Repository scope

This repository is **only** the reusable SDK. Forest Walk was removed from this repository and must be recovered from git history into the separate `ai-passport-template` repository. That template is also the place for a starter application, browser preview, device integration, and flashing/provisioning tooling; their migration and release validation are still pending.

No raylib, ESP-IDF, BSP, or browser APIs appear in SDK code or its public API.

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

## Driver contracts (for backend authors)

A platform backend implements the relevant `pub(open)` traits:

- `Clock` — `monotonic_ms()` and `sleep_ms()` for frame pacing.
- `DisplaySink` — `present(frame~ : @graphics.FrameView)` receives a synchronous, read-only view of the finished RGB565 canvas.
- `PcmSink` (in `audio`) — `write(samples~ : FixedArray[Int])` receives signed PCM16 mono sample blocks.
- `BatterySource` (in `battery`) — `percent()` and `millivolts()` return optional readings.

Backend glue stays thin and replaceable; all reusable logic is pure MoonBit in the packages above.

## Development

Run `moon check --target native --output-json` and `moon test --target native --output-json`, then the same checks with `--target js`. Run `moon info` to regenerate public interfaces and `moon fmt` to format MoonBit files. Review generated interface changes before release.
