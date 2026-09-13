# ai-passport.mbt

Reusable MoonBit SDK for the [FoloToy AI Passport](https://github.com/FoloToy/ai-passport) wearable.

Mooncakes module: `colmugx/ai-passport`.

The same pure-MoonBit application logic runs unchanged on a development host and on the device: the SDK defines the contracts, and each platform supplies thin backend implementations.

## Repository scope

This repository is **only** the reusable SDK. The GitHub Template repository (`ai-passport-template`) owns the Forest Walk starter application, the browser development preview (HTML Canvas + Keyboard + WebAudio), the ESP-IDF integration, the FoloToy BSP adapter, and flashing/provisioning tooling.

No raylib, ESP-IDF, BSP, or browser APIs appear in SDK code or its public API.

## Packages

| Package | Contents |
| --- | --- |
| `core` | `Point`, `Size`, `Rect`, `Color` (RGB565 conversion), `LOGICAL_WIDTH = 120`, `LOGICAL_HEIGHT = 160` |
| `graphics` | `Canvas` drawing (`clear`, `pixel`, `line`, `rect`, `fill_rect`, `sprite`, bitmap text), `SpriteSheet`, text metrics |
| `input` | Semantic `Button` (`Up` / `Down` / `Ok`), `ButtonEvent` (`Press` / `Click` / `DoubleClick` / `LongPress`), edge-detecting `InputState` |
| `music` | `Meter` (6/8), `Tempo` (dotted-quarter BPM), `Pitch` / `Note` / `Track` / `Song` (max four tracks), `Sequencer`, `TickClock` |
| `audio` | 16 kHz PCM16 mono `Synth` with four monophonic voices, five waveforms (`Pulse12`, `Pulse25`, `Pulse50`, `Triangle`, `Noise`), and a sample-accurate `Player` that owns the music transport (loop, pause/resume, beat sync) |
| `battery` | `BatterySource` trait + caching `Battery`; reads return `Int?` because the fuel-gauge chip can be absent |
| `driver` | Backend-facing contracts: `Clock`, `DisplaySink`, plus test fixtures (`ZeroClock`, `SinkProbe`) |

## Display model

The logical screen is fixed at **120×160** pixels for v0.1. Applications draw with logical coordinates; the backend scales/presents however the hardware requires. Colors are authored as RGB and quantized to **RGB565** by `Color::to_rgb565()` — the same quantized colors a preview and the device LCD show.

Graphics public APIs never expose strip rendering, framebuffers, or display-controller specifics.

## Input model

Buttons are semantic values — `Up`, `Down`, `Ok` — never GPIO or ADC channels. `InputState` turns raw press/release feeds into `pressed`, `just_pressed`, and `just_released` edges per frame via `advance()`.

## Music and audio

- 6/8 meter with dotted-quarter BPM tempo (default 76).
- `Song::new` accepts at most four tracks (typed `SongError.TooManyVoices`) and stores an **immutable snapshot**: the caller's authoring arrays are deep-copied, so mutating them afterwards cannot change a constructed song. Read access: `meter()`, `tempo()`, `ticks_per_eighth()`, `track_count()`.
- `Sequencer` walks a song with deterministic looping (arrival-based: the first step fires the tick-0 note starts); `length()` is the loop length in song ticks. `TickClock` converts elapsed samples into song ticks with exact integer accumulation (no drift), and `ticks_to_samples_exact` measures from the current clock phase to a future tick boundary.
- `Synth` renders 16 kHz signed PCM16 mono, mixes up to four monophonic voices, clamps to `[-32768, 32767]`, and is fully deterministic (same triggers → same PCM, including noise). Envelope stages are integer Bresenham ramps that reach their target exactly at the requested millisecond duration and can never stall.
- `Player` is sample-accurate: the transport starts on tick 0 (a song beginning with a note is audible from output sample 0), note gates release exactly on their musical tick boundary whatever the fractional clock carry, chunked rendering is sample-identical to one big render, and `beat()` counts dotted quarters from monotonically elapsed ticks — independent of loop length or wrap position.

## Battery

`BatterySource::percent` and `millivolts` return `Int?`: the CW2017 fuel gauge sits on I²C and may be absent, so "no reading" is part of the contract, not an error path. `Battery` caches readings behind an explicit `refresh()` (exactly one source read per refresh).

## Driver contracts (for backend authors)

A platform backend implements these `pub(open)` traits and nothing else:

- `Clock` — `monotonic_ms()` and `sleep_ms()` for frame pacing.
- `DisplaySink` — receives the finished `Canvas` on `present()`.
- `PcmSink` (in `audio`) — receives rendered PCM sample blocks.

Backend glue stays thin and replaceable; all reusable logic is pure MoonBit in the packages above.

## Development

```bash
moon check --target native && moon test --target native   # device-facing target
moon check --target js     && moon test --target js       # web preview target
moon info && moon fmt                                     # keep interfaces and formatting clean
```
