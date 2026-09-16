# AI Passport SDK — web host (ABI v0, internal/experimental)

`passport-host.js` is the SDK-owned, **application-agnostic** browser host
backend for compiled MoonBit wasm applications. It implements the frozen ABI v0
contract (framebuffer 120x160 RGB565 LE at byte offset 4096, length 38400; PCM
staging buffer at 42496; normalized PCM16 LE mono at 16000 Hz) and knows
nothing about any specific app: no
sprites, no BPM, no app state machines, no asset formats. App semantics live
entirely inside `app.wasm`.

Files:

| File | Purpose |
|---|---|
| `passport-host.js` | Host module: instantiation, imports, frame lifecycle, framebuffer blit, PCM transport (streamed + optional PCM asset mode), input, HUD. Exported factory `createHost()`; browser auto-boot at the bottom. Importable in Node with no DOM. |
| `pcm-worklet.js` | AudioWorklet processor `passport-pcm`: mono Float32 ring buffer, gapless scheduling at 16000 Hz, silence on underrun. |
| `index.html` | Minimal page: canvas, host-facts HUD, key hints. No frameworks, no CDN, no inline app logic. |
| `README.md` | This document. |

## Normalized PCM only

**This host plays only normalized PCM16 LE mono 16000 Hz**, delivered by either
producer mode:

1. **Streamed mode** (default): the app pushes PCM through `host_pcm_write`,
   and tests can use `__passportHost.feedNormalizedPcm`.
2. **PCM asset mode** (optional, see below): the host itself fetches an
   already-normalized `.pcm` artifact and feeds the SAME decode/queue/
   AudioWorklet path in bounded chunks.

**Authored MP3/WAV files are an asset-compiler concern outside this
repository** — no MP3/WAV decoding exists anywhere in the host. The asset
input format is strictly raw signed PCM16, little-endian, mono, 16000 Hz,
headerless; the byte length must be even and non-zero. Nothing resamples,
nothing sniffs container formats.

## PCM asset mode (normalized `.pcm` transport)

Host configuration only — never application semantics:

```js
const host = await createHost({
  canvas,
  pcmAssetUrl: "./assets/music.pcm", // or pcmAssetBytes (inline; mutually exclusive)
  pcmLoop: true, // default false: play to EOF, then stop feeding
});
```

- **Raw bytes are authoritative.** The artifact is fetched once and kept
  resident as the raw `ArrayBuffer`. A whole-track `Float32Array` copy is
  never created: decoding happens in fixed chunks of **3200 samples**
  (~200 ms), on demand, from a source cursor.
- **Bounded refill.** Chunks are decoded only while the decoded queue is
  below a budget: ~3200 samples (worklet mode) or 8192 samples (two
  ScriptProcessor pull buffers). Peak decoded-ahead is therefore bounded at
  budget + one chunk (≤ 11392 samples ≈ 0.7 s) plus the ~200 ms the worklet
  ring keeps (≤ 16384 samples hard ring cap). The pending queue, the worklet
  ring, and every decoded chunk are bounded; only the raw artifact itself is
  whole-track.
- **Sample-exact looping.** With `pcmLoop: true`, after the last sample the
  next supplied sample is sample 0 — a chunk never crosses the seam, so the
  output stream is exactly `s[0..N-1]` repeated: no silence insertion, no
  padding, no crossfade, no AudioContext restart. With `pcmLoop: false`
  (default), playback stops feeding at EOF; the transport then outputs its
  documented underrun silence and the position freezes at the asset length.
- **Playback position is unchanged** (`host_playback_pos_us`): total consumed
  output samples × 62.5 µs, monotonic across loops; volume/mute only touch
  the master GainNode, so they never stop the position clock. Loop-relative
  musical position can be derived app-side from `host_playback_pos_us` and
  the known asset duration.
- **Autoplay is a host concern.** The asset fetch is asynchronous and never
  blocks wasm frames, canvas, or input. A suspended AudioContext suspends
  consumption (position stays 0); `resumeAudio()` continues playback through
  the same transport with no app restart.
- **The two producer modes are explicitly exclusive.** `createHost` fails at
  boot when an asset is configured and the app module imports
  `passport.host_pcm_write` (config-level conflict), and on an asset host
  `feedNormalizedPcm`/the default `host_pcm_write` import throw clearly. They
  never silently mix.

Host-side asset facts (JS API only — deliberately NOT wasm imports):

| Member | Notes |
|---|---|
| `audioAssetLoaded` | `true` once the raw bytes are resident. |
| `audioAssetSamples` | Total PCM samples (`byteLength / 2`). |
| `audioAssetDurationUs` | `BigInt` µs of one full pass (`round(samples * 1e6 / 16000)`). |
| `audioAssetLooping` | Whether `pcmLoop` is on. |
| `audioAssetLoops` | Completed **consumption** passes (`floor(consumedSamples / assetSamples)`). |
| `audioAsset` | Full detail snapshot: `{configured, source, url, loaded, error, samples, byteLength, durationUs, looping, cursor, eof, chunkSamples, chunksDecoded, maxChunkSamples, pendingSamples, peakPendingSamples, loops}`. |
| `waitForAudioAsset()` | `Promise<void>`: resolves when loaded (immediately when no asset is configured); rejects on fetch/validation failure without ever blocking frames. |

A failed asset load (HTTP error, odd byte length, empty artifact) is an
audio-only degradation: the error is recorded (`audioAsset.error`, HUD status)
and app frames keep running.

`index.html` auto-boot accepts the same configuration through URL parameters:
`?pcm=<url>` (asset URL) and `?pcmLoop=1`. There is no default asset — the
parameter names a URL the page operator chooses.

## Bundle directory contract

The host is served from a directory (the "bundle") shaped like:

```
bundle/
├── index.html
├── passport-host.js
├── pcm-worklet.js
├── app.wasm          # compiled MoonBit wasm app (wasm backend, ABI v0)
└── assets/           # test/asset files (owned by later waves; see below)
```

- The host fetches `app.wasm` relative to its own module URL (i.e. the bundle
  directory); `index.html` loads `./passport-host.js` from the same directory.
- The host **never** reads `assets/` itself and never knows about `src/`,
  authored PNG/MP3/WAV sources, or ESP-IDF configuration. `assets/` belongs to
  the test wave (`hosts/web/test/**` exercises the normalized-PCM path via
  `feedNormalizedPcm`).
- `file://` will **not** work: ES module loading, `fetch("app.wasm")`, and
  AudioWorklet `addModule` all require http(s). Serve the bundle directory,
  e.g.:

  ```sh
  cd hosts/web   # or your assembled bundle dir
  python3 -m http.server 8000
  # open http://localhost:8000/
  ```

## Host-side ABI v0

### Imports — module `"passport"` (app declares, this host implements)

| Symbol | JS signature | Semantics |
|---|---|---|
| `host_battery_percent` | `() -> i32` | Fixture 0..100, or -1 = unavailable. Default 82; URL `?battery=NN` overrides; `?battery=none` gives -1. |
| `host_pcm_write` | `(ptr: i32, samples: i32) -> ()` | `samples` PCM16 LE mono 16000 Hz values at byte offset `ptr` in wasm memory. The host decodes and copies synchronously (Int16 view -> Float32 /32768) and never blocks the wasm call. |
| `host_set_volume` | `(volume: i32) -> ()` | Master gain, clamped 0..100, mapped linearly to a GainNode (`volume/100`). |
| `host_set_muted` | `(muted: i32) -> ()` | 0/1. Muted forces gain 0; the playback-position clock keeps running. |
| `host_playback_pos_us` | `() -> i64` | Best-effort µs of normalized PCM scheduled to output since playback start (BigInt at the boundary). Returns `0n` before any playback and when no audio backend exists. |

### Exports — app provides (host validates and drives)

| Symbol | Signature | Semantics |
|---|---|---|
| `_start` | `() -> ()` | Called exactly once after instantiation; app `main` initializes and returns (no loop). |
| `passport_frame` | `(now_us: i64) -> ()` | One tick; `now_us` is a JS BigInt. |
| `passport_input` | `(button: i32, pressed: i32) -> ()` | button 0=Up 1=Down 2=Ok; pressed 1=press 0=release. All queued events are flushed before the next `passport_frame`. |
| `passport_fb_ptr` | `() -> i32` | Must be 4096 (validated at boot; mismatch throws with a hint about `heap-start-address` / `link.wasm.exports`). |
| `passport_fb_len` | `() -> i32` | Must be 38400. |
| `passport_frame_dirty` | `() -> i32` | 1 if the framebuffer was written since last consume. |
| `passport_frame_consume` | `() -> ()` | Clears the dirty flag. |
| `memory` | — | The app's exported linear memory. |

### Memory map (byte addresses; constants mirrored from `src/hostabi`)

| Range | Contents |
|---|---|
| `[0, 4096)` | Null-page guard — host never touches. |
| `[4096, 42496)` | Framebuffer: 120x160 RGB565 uint16 **little-endian**, row-major, index `y*120+x`. Host **reads only**. |
| `[42496, 58880)` | PCM staging buffer (8192 PCM16 samples). **App-internal**: the host never addresses it; it only reads the exact `[ptr, ptr + samples*2)` ranges the app passes to `host_pcm_write`. |
| `[65536, ...)` | MoonBit heap (`heap-start-address = 65536`); `[0, 65536)` is ABI-reserved and the MoonBit heap never allocates below it. |

### Lifecycle

1. Host instantiates `app.wasm` with the `passport` import object.
2. Host calls `_start()` once (init runs; `main` returns).
3. Per rAF: flush queued `passport_input` events, then
   `passport_frame(BigInt(Math.round(performance.now() * 1000)))`.
4. If `passport_frame_dirty() == 1`: convert the RGB565 framebuffer view into
   the reused `ImageData` and `putImageData(0, 0)`, then
   `passport_frame_consume()`.
5. Views (`Uint16Array` framebuffer view, `ImageData`, its `Uint32Array`) are
   allocated once and re-created **only** if `memory.buffer` was detached by
   wasm memory growth.

The only per-frame wasm calls are the lifecycle exports above — there are no
per-pixel wasm calls and no full-frame JS allocation per rAF after init.

## Keyboard map

| Key (`KeyboardEvent.code`) | Button |
|---|---|
| `ArrowUp`, `KeyW` | Up (0) |
| `ArrowDown`, `KeyS` | Down (1) |
| `Enter`, `Space` | Ok (2) |

Arrows and Space `preventDefault()` (no page scrolling). Auto-repeat keydown
events are ignored; keyup always releases. Events queue and are flushed FIFO
before each frame. Press any key or click once to unlock the AudioContext.

## URL parameters

| Param | Effect |
|---|---|
| `?battery=NN` | Battery fixture percent 0..100 (default 82). |
| `?battery=none` | Battery unavailable (`host_battery_percent` returns -1). |
| `?scale=NN` | Integer CSS scale of the 120x160 canvas (default 3 => 360x480 CSS px). |
| `?pcm=<url>` | PCM asset mode: URL of a normalized `.pcm` artifact (see above). |
| `?pcmLoop=1` | Loop the PCM asset at the exact sample boundary (with `?pcm=`). |

## Audio pipeline and playback position

- `host_pcm_write` copies `samples` int16 values out of wasm memory and
  decodes them to Float32 (`/32768`) synchronously; chunks land in a
  main-thread queue.
- Primary transport: `pcm-worklet.js` (AudioWorklet, real-time thread). The
  main thread forwards whole chunks while the worklet ring holds less than
  ~200 ms (3200 samples); the ring itself is ~1 s (16384 samples). Underrun
  outputs silence; nothing ever blocks the wasm call.
- Fallback transport: ScriptProcessorNode, used **only** when the engine has
  no usable AudioWorklet. ScriptProcessor is deprecated and runs on the main
  thread (it can jitter under load), so it is a compatibility path, not the
  design; its failures would be a browser bug, not a host feature.
- Volume/mute are a master `GainNode` after the source, so muting does not
  stall the position clock.
- `AudioContext` is constructed with `{ sampleRate: 16000 }` so no resampling
  is needed. Engines that ignore the hint would play at the wrong pitch (see
  limitations).

**Position formula** (`host_playback_pos_us` / `host.playbackPosUs()`):

```
position_us = round((consumedSamples + max(0, ctx.currentTime - snapshotCtxTime) * 16000)
                    * 1e6 / 16000)
```

where `{ consumedSamples, snapshotCtxTime }` is refreshed by the worklet's
consumption reports (~every 32 ms) or each ScriptProcessor pull. Before the
first report — and always when no audio backend exists — it returns `0n`.

## Test surface

In the browser the booted host is `window.__passportHost`; in Node it is the
object returned by `createHost()` (same implementation, no DOM required).

| Member | Notes |
|---|---|
| `frameCount` | Frames ticked since boot. |
| `lastNowUs` | `BigInt` µs of the last `passport_frame`, or `null`. |
| `inputQueueLength` | Queued, not-yet-flushed input events. |
| `batteryPercent` | Fixture value (-1 = unavailable). |
| `volume` / `muted` | Current master state. |
| `setVolume(v)` | 0..100, clamped; same code path as the `host_set_volume` import. |
| `setMuted(b)` | Same code path as the `host_set_muted` import. |
| `playbackPosUs()` | `BigInt` µs (formula above); `0n` before playback. |
| `feedNormalizedPcm(Int16Array \| ArrayBuffer)` | Injects PCM16 LE through the SAME decode+queue path as `host_pcm_write` (does not touch `pcmStats`, which counts the wasm import only). Throws on an asset-configured host (exclusive producer modes). |
| `pcmStats` | `{ bytesReceived, calls, droppedSamples }` — `calls` counts every `host_pcm_write` invocation (including one rejected by bounds validation); `bytesReceived` counts only bytes successfully copied out. Both come from the wasm import path only. `droppedSamples` is an extra observability field beyond the frozen minimum. |
| `audioAssetLoaded` / `audioAssetSamples` / `audioAssetDurationUs` / `audioAssetLooping` / `audioAssetLoops` / `audioAsset` / `waitForAudioAsset()` | PCM asset facts (see "PCM asset mode" above); neutral zeros / immediate resolve when no asset is configured. |

Additional seams (documented, same object):

| Member | Notes |
|---|---|
| `queueInput(button, pressed)` | Push a semantic button event without the keyboard. |
| `tick(nowUs?)` | Run exactly one frame cycle (flush input -> frame -> dirty blit/consume) without rAF — the deterministic way to drive frames. |
| `start()` / `stop()` | rAF loop (browser) or 16 ms interval (Node fallback). |
| `getFramebufferView()` | `Uint16Array(19200)` RGB565 view; transparently re-created after memory growth. |
| `onAudioReport({filled, consumed, underruns, dropped})` | Normally wired to the worklet port; tests may call it to simulate consumption and exercise `playbackPosUs()`. |
| `resumeAudio()` | AudioContext unlock (called on first gesture in the browser). |
| `imports` / `exports` / `memory` / `audio` | The import object used, the app's wasm exports, the linear memory, and `{ enabled, kind, ctx, gain, node, underruns, dropped, workletError, reason }`. |
| `dispose()` | Removes listeners/timers, stops the loop, closes the AudioContext. |

### `createHost(options)`

```js
import { createHost, BUTTON, FB_PTR, FB_LEN, SAMPLE_RATE } from "./passport-host.js";

const host = await createHost({
  wasmBytes,            // ArrayBuffer/TypedArray (Node) — or wasmUrl/fetch below
  wasmUrl,              // default: new URL("app.wasm", import.meta.url)
  canvas,               // HTMLCanvasElement; omit in Node
  audioContextFactory,  // ({sampleRate}) => ctxLike — Node fake-context seam
  workletUrl,           // default: sibling pcm-worklet.js
  pcmAssetUrl,          // PCM asset mode (or pcmAssetBytes); app must NOT
  pcmAssetBytes,        //   import host_pcm_write (exclusive producer modes)
  pcmLoop,              // default false
  imports: { passport: { host_battery_percent: () => 50 } }, // per-key overrides
  nowUs: () => 0n,      // deterministic frame clock (default: performance.now())
  batteryPercent,       // default: URL ?battery=, else 82
  volume, muted, scale, // initial host state
});
```

Node fake-AudioContext contract (what `audioContextFactory` must return for
audio to be "enabled"): `{ currentTime: number, destination: any,
createGain: () => ({ gain: { value }, connect() {} }), state?: string }`.
Without `audioWorklet`/`createScriptProcessor` the host sets `audio.kind =
"none"`, keeps queueing decoded PCM, and tests can drive `playbackPosUs()` via
`onAudioReport()` + a mutating `currentTime`.

## JS responsibilities vs app semantics

| This host (JS) | The wasm app (MoonBit) |
|---|---|
| Instantiation, `_start`, frame/input delivery order | All application state, rendering, logic |
| RGB565 -> RGBA presentation of the frozen framebuffer | What gets drawn into the framebuffer |
| Normalized-PCM scheduling, gain, position | What PCM gets streamed (via `host_pcm_write`) |
| Battery fixture, keyboard mapping, HUD | Battery/input/music *use* via the SDK packages |

## Known limitations

- **Big-endian platforms are rejected at boot** with a clear error: frozen
  ABI v0 framebuffer and PCM are little-endian.
- **Underrun policy**: the worklet outputs silence; `host_playback_pos_us`
  only advances with real consumption, but the interpolated position between
  ~32 ms reports keeps advancing with `ctx.currentTime`, so during underrun
  the reported position is optimistic (best-effort by contract). In PCM asset
  non-loop mode this also means the interpolated position can drift past EOF
  between the last report and a read; the consumption-based facts
  (`audioAssetLoops`, worklet reports) stay exact.
- **Position granularity**: consumption reports arrive roughly every 32 ms;
  between reports the position is interpolated from `ctx.currentTime`. The
  asset facts derived from them (`audioAssetLoops`) lag consumption by at
  most one report (~512 samples).
- **Sample rate hint**: if an engine ignores `new AudioContext({sampleRate:
  16000})`, audio plays at the wrong pitch; no host-side resampler exists.
  PCM asset mode inherits this: the artifact is played strictly at 16 kHz.
- **PCM asset mode is strictly PCM16 LE mono 16000 Hz**: odd-length or empty
  artifacts fail the asset (never the app). There is no container parsing by
  design — a mislabeled MP3/WAV file plays as noise, not an error.
- **Tiny assets in worklet mode** (fewer samples than one 3200-sample chunk)
  produce many small transport messages; correct, but such assets are only
  meaningful in tests. Real assets are chunk-multiples in practice.
- **ScriptProcessor fallback** is deprecated, main-thread, and best-effort.
- **`?scale=0`/garbage** falls back to the default scale 3.
- The host is served over http(s) only (no `file://`), per the bundle
  contract above.
