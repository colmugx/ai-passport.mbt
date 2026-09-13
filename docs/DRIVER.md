# Driver contracts

Backends implement the same semantic contracts on native hosts and devices. These are the public `pub(open)` traits in the generated package interfaces:

| Package | Trait | Required methods |
| --- | --- | --- |
| `battery` | `BatterySource` | `percent(Self) -> Int?`, `millivolts(Self) -> Int?` |
| `driver` | `Clock` | `monotonic_ms(Self) -> Int`, `sleep_ms(Self, ms~ : Int) -> Unit` |
| `driver` | `DisplaySink` | `present(Self, frame~ : @graphics.FrameView) -> Unit` |
| `audio` | `PcmSink` | `write(Self, samples~ : FixedArray[Int]) -> Unit` |

`BatterySource` may return `None` when a reading is unavailable. `Battery::refresh()` updates the cached values; callers choose a suitable polling cadence. `Battery::fixture(percent~)` is a deterministic test fixture. `ZeroClock`, `SinkProbe`, and `BufferSink` are package-provided test implementations. Platform implementations belong outside the reusable SDK.

## Display lifetime and row contract

`DisplaySink::present` receives a read-only `@graphics.FrameView` sharing the canvas's private `FixedArray[UInt16]` RGB565 storage. Consume it synchronously; after the source canvas mutates, the view no longer represents the presented frame. Use `width()`, `height()`, and `copy_rgb565_row(y~, out~ : FixedArray[Int]) -> Int`. The copy returns zero for an out-of-range row, copies a fitting prefix into an undersized output, and leaves surplus output cells unchanged. Compare the returned count with `width()` when a complete row is required. No framebuffer ownership or strip-rendering detail is exposed.

## Input, clock, and audio

Backends translate physical controls to `Button::Up`, `Down`, and `Ok`, then feed `InputState::press` and `release`. The public `ButtonEvent` values are `Press`, `Click`, `DoubleClick`, and `LongPress`; `InputState` exposes pressed and edge state. `Clock` provides monotonic milliseconds and sleep for frame pacing; wall time does not drive the music transport. `Player` owns the authoritative sample clock. Feed `Player::render` actual sample counts from the audio callback or task, then pass its 16000 Hz signed PCM16 mono output to `PcmSink::write`. The PCM sink receives `FixedArray[Int]`; the values are bounded to signed 16-bit range.
