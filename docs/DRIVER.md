# Driver contracts

Backends implement the same semantic contracts on native hosts and devices. These are the public `pub(open)` traits in the generated package interfaces:

| Package | Trait | Required methods |
| --- | --- | --- |
| `battery` | `BatterySource` | `percent(Self) -> Int?`, `millivolts(Self) -> Int?` |
| `driver` | `Clock` | `monotonic_ms(Self) -> Int`, `sleep_ms(Self, ms~ : Int) -> Unit` |
| `driver` | `DisplaySink` | `present(Self, frame~ : @graphics.FrameView) -> Unit` |

`BatterySource` may return `None` when a reading is unavailable. `Battery::refresh()` updates the cached values; callers choose a suitable polling cadence. `Battery::fixture(percent~)` is a deterministic test fixture. `ZeroClock` and `SinkProbe` are package-provided test implementations. Platform implementations belong outside the reusable SDK.

`audio.Sound` is a separate open resource contract, implemented by the
application's generated `@sounds.Sound` enum. Its `resource_id(Self) -> UInt`
method carries the declaration-order bank ID into the portable playback API;
applications use generated constructors rather than numeric IDs. It is not a
driver, mixer node, stream, codec, or claim that future audio sources must use
sound banks.

`audio.Playback` is an opaque instance handle. `audio.play(sound,
looping=false)` returns `Playback?` so a Host with no free playback slot fails
explicitly without stealing another sound. `pause`, `resume`, `stop` and
`position` operate on that instance, allowing one `Sound` to overlap with
itself. `position` returns microseconds as `Int64?` and becomes `None` when the
Host no longer has a live position for the handle. MoonBit reserves `loop` as
a keyword, so the labeled play option is `looping`.

## Display lifetime and row contract

`DisplaySink::present` receives a read-only `@graphics.FrameView` sharing the canvas's private `FixedArray[UInt16]` RGB565 storage. Consume it synchronously; after the source canvas mutates, the view no longer represents the presented frame. Use `width()`, `height()`, and `copy_rgb565_row(y~, out~ : FixedArray[Int]) -> Int`. The copy returns zero for an out-of-range row, copies a fitting prefix into an undersized output, and leaves surplus output cells unchanged. Compare the returned count with `width()` when a complete row is required. No framebuffer ownership or strip-rendering detail is exposed.

## Input and clock

Backends translate physical controls to `Button::Up`, `Down`, and `Ok`. The application receives press/release edges through `Application::button` and recognized `Press`, `Click`, `DoubleClick`, and `LongPress` events through the optional `Application::button_event` method. `InputState` exposes pressed and edge state; a repeated press while held does not create another edge. Web gesture recognition tracks each semantic button independently. The FoloToy Host forwards BSP-recognized events; its one-line ADC ladder does not support reliable physical chords. `Clock` provides monotonic milliseconds and sleep for frame pacing. Sound playback crosses only the internal Host sound-operation boundary; there is no public PCM sink, mixer graph, codec, synthesis, or sequencing contract.
