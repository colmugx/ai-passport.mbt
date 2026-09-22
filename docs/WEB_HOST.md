# Web Host contract

The Web Host runs the same MoonBit application contract as a physical Host.
It owns browser transport only: a 240×320 RGB565 framebuffer, semantic input,
battery facts, master audio output, and playback of the project's APSB sound
bank. It contains no application behavior and no audio-authoring pipeline.

The ABI described here is internal and co-versioned with the SDK. Application
code uses `application`, `graphics`, `input`, `audio`, and `battery`; it never
imports this ABI directly.
The full-resolution framebuffer, microphone scratch memory, backlight, and
power imports change the internal binary layout and imports. Rebuild the
application and Host bundle together; an older bundle cannot run this ABI.

## Bundle

`passport build --host web` creates `.passport/web/`:

```text
app.wasm
index.html
passport-host.js
sound-worklet.js
sounds.bank
assets/...
```

`sounds.bank` is always present. A project without sounds receives the valid
16-byte empty APSB v1 bank. Sound selection never travels through URL query
parameters; the normal entry URL is `/index.html`. The optional `battery` and
`scale` query parameters are Host/debug facts only. The reference page keeps
the canvas at its native 240×320 CSS size by default; pass `?scale=N` only when
an enlarged debug preview is useful.

## Wasm ABI

The application exports:

| Export | Purpose |
| --- | --- |
| `_start()` | Initialize the application exactly once and return. |
| `passport_frame(now_us: i64)` | Advance and present one frame. |
| `passport_input(button: i32, pressed: i32)` | Deliver `Up`, `Down`, or `Ok`. |
| `passport_fb_ptr() -> i32` | Return the framebuffer address. |
| `passport_fb_len() -> i32` | Return its byte length. |
| `passport_frame_dirty() -> i32` | Report whether a new frame is ready. |
| `passport_frame_consume()` | Mark the current frame consumed. |

The Host provides the `passport` import module:

| Import | Purpose |
| --- | --- |
| `host_battery_percent() -> i32` | Return 0–100 or -1 when unavailable. |
| `host_set_volume(value: i32)` | Set application-wide master volume. |
| `host_set_muted(value: i32)` | Set application-wide master mute. |
| `host_backlight_level() -> i32` | Read the Web presentation brightness, 0..100. |
| `host_set_backlight(value: i32)` | Set Web canvas presentation brightness. |
| `host_sound_play(sound_id: i32, looping: i32) -> i32` | Start one playback; return a positive handle or -1. |
| `host_sound_pause(handle: i32)` | Pause that playback. |
| `host_sound_resume(handle: i32)` | Resume that playback. |
| `host_sound_stop(handle: i32)` | Stop and invalidate that playback. |
| `host_sound_position_us(handle: i32) -> i64` | Return its position or -1 for an invalid handle. |
| `host_capture_start() -> i32` | Request microphone capture; returns a capture status code. |
| `host_capture_status() -> i32` | Report unavailable, idle, requesting, recording, denied, or failed. |
| `host_capture_stop()` | Release the microphone and discard unread samples. |
| `host_capture_read(max_samples: i32) -> i32` | Write signed PCM16 to the reserved scratch region. |
| `host_capture_dropped() -> i32` | Report samples lost to bounded queue overflow. |
| `host_power_request(wake_after_ms: i32) -> i32` | Request frame suspension; -1 means button wake only. |
| `host_wake_reason() -> i32` | Return 0 before wake, 1 button, 2 timer, or 3 other. |

The framebuffer begins at byte offset 4096, contains 240×320 little-endian
RGB565 pixels in row-major order, and occupies 153,600 bytes. Microphone reads
use a separate scratch region at offset 196,608 (2,048 bytes). The application
heap begins at 262,144. Sound-bank payloads do not pass through Wasm memory: the Host
loads and validates `sounds.bank` itself and addresses resources by Sound ID.

## Sound runtime

The Web Host validates APSB before application startup. Malformed magic,
version, index layout, offsets, sample counts, or trailing bytes fail the boot
with a specific error. The input contract is headerless signed PCM16
little-endian, mono, 16000 Hz; the browser runtime does not decode or resample
authoring formats.

Eight playback slots are available. Playing the same Sound twice allocates two
independent handles. Slot exhaustion returns failure and never steals another
playback. Pause, resume, stop, and position are per handle. The AudioWorklet
sums active sources and clamps the result; a ScriptProcessor fallback keeps the
same semantics where AudioWorklet is unavailable. Master volume and mute are
applied after mixing and do not change playback positions.

## Frame and input flow

The Host calls `_start` once. Each animation frame it flushes queued semantic
input, calls `passport_frame`, and copies the framebuffer to the canvas only
when dirty. Presentation is synchronous with respect to the Wasm memory view.
Keyboard mapping is ArrowUp/W, ArrowDown/S, and Enter/Space.

## Verification

From the repository root:

```sh
moon build --target wasm --release
moon build --target wasm
node hosts/web/test/run-tests.mjs
```

The suite proves both build profiles exclude the removed single-PCM imports,
validates APSB failures, overlapping playback and slot behavior, exercises the
MoonBit Sound API through the Host, builds downstream CLI fixtures, and runs a
real Chromium AudioWorklet proof.
