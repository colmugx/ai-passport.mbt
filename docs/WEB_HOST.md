# Web host (wasm backend) — ABI v0

> **Status: INTERNAL, EXPERIMENTAL.** ABI v0 is *not* a frozen public SDK API
> and may change or be withdrawn in later rounds. The target backend is the
> MoonBit **`wasm`** target (not `js`, not `wasm-gc`).
>
> The host-side reference is `hosts/web/README.md`; the test/tooling reference
> is `hosts/web/test/README.md`. When those and this file disagree, the code
> wins: constants live in `src/hostabi/constants.mbt` and are mirrored as
> exported constants in `hosts/web/passport-host.js`.

## What this is (and is not)

- `hosts/web/passport-host.js` is the SDK-owned, **application-agnostic** wasm
  host backend: it implements one contract (ABI v0) and knows nothing about
  any application — no sprites, no BPM, no app state machines, no asset
  formats. Application semantics live entirely inside the compiled
  `app.wasm`.
- It is a host **backend** in the sense of the architecture rule "host and
  device backends implement the same SDK semantics": MoonBit app code uses
  the same `Canvas`, `InputState`, `Battery`, and `PcmSink` contracts that
  native and JS backends see (`src/hostabi/bridge.mbt` adapts them to the raw
  wasm boundary).
- It is **not** an application preview and not an application template, and
  it is not written in MoonBit. All browser code lives in `hosts/web/*.js`
  assets; SDK MoonBit code contains no browser APIs.
- Only i32/i64 primitives and explicit linear-memory byte offsets/lengths
  cross the boundary. No MoonBit struct/array/string layout is part of the
  ABI, and no MoonBit object address is ever read or exposed
  (`src/hostabi/wasm_ffi.mbt`, `src/hostabi/bridge.mbt`).

## Linear memory map

The app module **exports** its linear memory (export name `memory`); JS never
imports memory in v0. The fixture app's `src/fixture/moon.pkg` sets
`heap-start-address = 65536` (one 64 KiB page), which makes the MoonBit heap
start at 65536, so region `[0, 65536)` is ABI-reserved and the MoonBit GC
never allocates there — this is what makes raw byte-addressed access through
inline WAT safe (`src/hostabi/constants.mbt`, `ABI_HEAP_START`).

| Byte range | Contents |
|---|---|
| `[0, 4096)` | Null-page guard, unused; host never touches it. |
| `[4096, 42496)` | **Framebuffer**: 120x160 RGB565 `u16`, little-endian, row-major, index `y*120+x` (`FRAMEBUFFER_PTR = 4096`, `FRAMEBUFFER_LEN = 38400` in `src/hostabi/constants.mbt`). App writes via the bridge; host reads only. |
| `[42496, 58880)` | **PCM staging buffer**: 16384 bytes = 8192 PCM16 LE samples (`PCM_STAGE_PTR = 42496`, `PCM_STAGE_CAPACITY_BYTES = 16384`, `PCM_STAGE_CAPACITY_SAMPLES = 8192`). App-internal staging; the host only ever reads the exact `[ptr, ptr + samples*2)` range an app passes to `host_pcm_write`. |
| `[58880, 65536)` | Unassigned ABI reserve. |
| `[65536, ...)` | MoonBit heap (`heap-start-address = 65536`). |

The framebuffer is **persistent**: it is a fixed reserved region, allocated
once per module instance. On the wasm side, the bridge's row-decode scratch
buffer is a private field allocated once in `HostBridge::new`
(`src/hostabi/bridge.mbt`), so `DisplaySink::present` performs zero
steady-state allocations. On the JS side all presentation buffers (the
`Uint16Array` framebuffer view, the `ImageData` and its `Uint32Array`) are
allocated once; a presented frame performs **zero** full-frame JS
allocations. Views are re-created only when wasm memory growth detaches
`memory.buffer` — that single case is covered by the passing "memory growth"
integration suite (`hosts/web/test/run-tests.mjs`, suite 7).

## Import table — module `"passport"`

Declared as wasm-target-gated externs in `src/hostabi/wasm_ffi.mbt`
(`src/hostabi/moon.pkg` compiles that file only for `wasm`); implemented by
the JS host (`hosts/web/passport-host.js`).

| Symbol | Signature | Semantics |
|---|---|---|
| `passport.host_battery_percent` | `() -> i32` | Battery reading: `0..100`, or `-1` = unavailable. The bridge maps any negative wire value to `None` (`src/hostabi/bridge.mbt`); the host default is the fixture 82. |
| `passport.host_pcm_write` | `(ptr: i32, samples: i32) -> ()` | `samples` PCM16 LE mono 16000 Hz values at byte offset `ptr`. The host decodes and copies synchronously before returning, so the app may restage immediately. Written through the bridge, `samples` never exceeds 8192. |
| `passport.host_set_volume` | `(volume: i32) -> ()` | Master output gain, clamped 0..100 by the host, mapped linearly to a GainNode (`volume/100`). |
| `passport.host_set_muted` | `(muted: i32) -> ()` | `0` = audible, `1` = muted. Muting forces gain 0 but the playback-position clock keeps running. |
| `passport.host_playback_pos_us` | `() -> i64` | Host best-effort microseconds of normalized PCM output since playback start (BigInt at the JS boundary; `0n` before any playback and with no audio backend). Apps must compare deltas, never absolute values. |
| `passport.host_sound_play` | `(sound_id: i32, looping: i32) -> i32` | Starts one APSB entry and returns a positive independent playback handle. Returns `-1` for invalid IDs, unavailable audio or eight exhausted slots; it never steals another playback. |
| `passport.host_sound_pause` | `(handle: i32) -> ()` | Pauses one live playback. Unknown/dead handles are no-ops. |
| `passport.host_sound_resume` | `(handle: i32) -> ()` | Resumes one paused playback. Unknown/dead handles are no-ops. |
| `passport.host_sound_stop` | `(handle: i32) -> ()` | Stops one playback and invalidates its handle. |
| `passport.host_sound_position_us` | `(handle: i32) -> i64` | Loop-relative playback position in microseconds, or `-1` for a dead handle. |

## Export table

Exported from the fixture main package via
`options(link: { "wasm": { "exports": [...] } })` in `src/fixture/moon.pkg`
(plus the wasm default `_start`):

| Symbol | Signature | Semantics |
|---|---|---|
| `memory` | — | The app's exported linear memory. |
| `_start` | `() -> ()` | Wasm default entry; host calls it exactly once before any `passport_*` export. App `main` initializes and **returns** — there is no loop; the host paces frames. |
| `passport_frame` | `(now_us: i64) -> ()` | One tick: advance clock, apply input edges, refresh battery, render, stream PCM, present (marks framebuffer dirty). `now_us` is a JS BigInt. |
| `passport_input` | `(button: i32, pressed: i32) -> ()` | button `0`=Up `1`=Down `2`=Ok (`@hostabi.to_button`, `src/hostabi/buttons.mbt`); pressed `1`=press `0`=release. Unknown codes are ignored. Queued events are flushed before the next `passport_frame`. |
| `passport_fb_ptr` | `() -> i32` | Byte offset of the persistent framebuffer (4096). The host validates this at boot and throws with a `heap-start-address` hint on mismatch. |
| `passport_fb_len` | `() -> i32` | 38400. |
| `passport_frame_dirty` | `() -> i32` | `1` if the framebuffer was written since the last consume. |
| `passport_frame_consume` | `() -> ()` | Clears the dirty flag; safe to call while clean. |

## Lifecycle sequence

1. Host instantiates `app.wasm` with the `passport` import object.
2. Host calls `_start()` once; the app's `main` runs one-time init (fixture:
   mirrors `host_set_volume(70)`, `host_set_muted(0)`, probes
   `host_playback_pos_us` — `src/fixture/state.mbt`) and returns.
3. Per animation frame: flush all queued `passport_input` events, then call
   `passport_frame(BigInt(Math.round(performance.now() * 1000)))`.
4. If `passport_frame_dirty() == 1`: convert the RGB565 framebuffer view into
   the reused `ImageData`, `putImageData(0, 0)` on the 120x160 canvas, then
   `passport_frame_consume()`.
5. Views are re-created only if `memory.buffer` was detached by memory
   growth; otherwise every buffer is allocated once.

## Framebuffer transport path

```
SDK Canvas (RGB565 u16/pixel, logical 120x160)
  -> Canvas::frame_view() : read-only FrameView (no full-frame copy)
  -> HostBridge DisplaySink::present  (src/hostabi/bridge.mbt:
       row-by-row FrameView::copy_rgb565_row into a scratch row allocated
       once in the constructor, fixed stride, clipped to logical size so
       the region can never be overrun — zero steady-state allocations)
  -> inline-WAT i32.store16 ("store_u16", src/hostabi/wasm_ffi.mbt)
  -> linear memory at [4096, 42496)
  -> JS Uint16Array view over memory.buffer (reused; re-bound only on detach)
  -> rgb565ToRgba8888 into the reused ImageData/Uint32Array
  -> canvas.putImageData(0, 0)
```

The only wasm calls per presented frame are the lifecycle exports — there
are no per-pixel wasm calls. Graphics public APIs stay free of framebuffer,
strip-rendering, or controller details; `copy_rgb565_row` is the only
sanctioned read path.

## PCM transport path

```
app signal generator (reused FixedArray[Int], PCM16-range samples)
  -> @audio.PcmSink = HostBridge::write (src/hostabi/bridge.mbt:
       clamp_pcm16 + pcm16_le_bits, src/hostabi/pcm16.mbt)
  -> staged via store_u16 at [42496, ...), <= 8192 samples per chunk
  -> host_pcm_write(PCM_STAGE_PTR, n)   (one call per chunk, in order)
  -> JS host decodes Int16 LE -> Float32 (/32768) synchronously, queues
  -> main thread forwards whole chunks to the AudioWorklet ring while the
     ring holds < ~200 ms (hosts/web/pcm-worklet.js: mono Float32 ring,
     ~1 s / 16384 samples, gapless scheduling at 16000 Hz, silence on
     underrun)
  -> output; master GainNode applies volume/mute after the source
```

A ScriptProcessorNode fallback exists only where AudioWorklet is unavailable
(see Limitations). The host plays **normalized PCM16 LE mono 16000 Hz only**;
authored MP3/WAV decoding is an asset-compiler concern outside this
repository (`hosts/web/README.md`).

### PCM asset mode (normalized `.pcm` artifact transport)

Besides the streamed `host_pcm_write` producer, the host can itself play an
already-normalized `.pcm` artifact — the SAME bytes an ESP32-class device
would stream from flash. This is host configuration, never application
semantics:

```
createHost({ pcmAssetUrl: "./assets/music.pcm", pcmLoop: true })
                     |
   fetch (async, never blocks frames) -> raw ArrayBuffer (authoritative,
   resident — no whole-track Float32 copy is ever created)
                     |
   bounded refill (demand-driven): decode PCM16 LE -> Float32 (/32768) in
   fixed 3200-sample chunks from a source cursor, only while the decoded
   queue is under budget (3200 samples worklet-side / 8192 script-side)
                     |
   the SAME enqueue/pump/AudioWorklet transport as host_pcm_write
```

Contract highlights (all pinned by suites in `hosts/web/test`):

- **Strict input**: signed PCM16 LE mono 16000 Hz, headerless, even non-zero
  byte length. Nothing decodes MP3/WAV, resamples, or sniffs formats.
- **Bounded**: peak decoded-ahead is budget + one chunk (≤ 11392 samples);
  every decoded chunk ≤ 3200 samples; the worklet ring keeps its ≤ 16384
  -sample cap. Only the raw artifact is whole-track.
- **Sample-exact loop**: a chunk never crosses the loop seam, so
  `pcmLoop: true` produces exactly `s[0..N-1]` repeated — no silence,
  padding, crossfade, or AudioContext restart. `pcmLoop: false` stops
  feeding at EOF.
- **Position unchanged**: `host_playback_pos_us` remains total consumed
  output samples × 62.5 µs, monotonic across loops; volume/mute touch only
  the master GainNode. Loop-relative musical position is derived app-side
  from the position and the known asset duration; host-side facts
  (`audioAssetSamples`, `audioAssetDurationUs`, `audioAssetLoops`, the
  `audioAsset` detail snapshot, `waitForAudioAsset()`) are JS-API-only and
  deliberately NOT new wasm imports.
- **Exclusive producers**: `createHost` fails at boot when an asset is
  configured and the app module imports `passport.host_pcm_write` (the
  module import table is inspected before instantiation); on an asset host
  `feedNormalizedPcm` and the default `host_pcm_write` import throw clearly.
- **Autoplay-safe**: the fetch is asynchronous and a suspended AudioContext
  suspends consumption only — wasm frames, canvas, and input never block;
  `resumeAudio()` continues through the same transport with no restart.
- **Failure is audio-only**: an HTTP error, odd-length, or empty artifact
  rejects `waitForAudioAsset()` and records `audioAsset.error` while the app
  keeps running.

`index.html` accepts the same configuration via `?pcm=<url>` and
`?pcmLoop=1`; there is no default asset and no project-specific name
anywhere in the host (`hosts/web/README.md` "PCM asset mode").

## Determinism rules

- Frame content is a pure function of (frame index N, input-derived
  selection, mute flag, battery fixture). `now_us` is fed to the clock but
  **never drawn**. The fixture uses no floating point anywhere.
- All raw memory access is integer-only inline WAT; bridge logic is pure
  integer math, which is why the whole `src/hostabi` package compiles and is
  unit-tested on native, js, and wasm alike (the former off-wasm test gating
  was removed in commit 24dd905; the wasm test module declares the
  `passport.*` externs but the tests never call them, which the wasm runner
  tolerates).
- The fixture PCM is a frozen integer square wave
  `sample(n) = ((n >> 4) & 1) == 1 ? -4000 : 4000` (500 Hz at 16000 Hz,
  amplitude 4000), 266 samples pushed per `passport_frame` from a global
  sample counter starting at frame 0 (`src/fixture/frame.mbt`,
  `src/fixture/state.mbt`).
- These rules are what make the golden-pixel and waveform-equality tests
  below possible: identical wasm bytes produce identical pixels and sample
  streams on every engine.

## Endianness

Little-endian is **guaranteed by the WebAssembly ISA itself**: the wasm spec
defines linear memory as byte-addressed little-endian, so `i32.store16`
writes the low 16 bits in LE byte order on every engine — the same binary
produces identical bytes everywhere (`src/hostabi/wasm_ffi.mbt`,
`store_u16`/`load_u16` docs). This is a property of the target, not of host
chance. As defense in depth for the JS side, the host probes
`Uint8Array/Uint16Array` byte order at boot and **rejects big-endian
platforms** with a clear error (`requireLittleEndian`,
`hosts/web/passport-host.js`).

## JS responsibilities vs MoonBit-resident semantics

The split is absolute: no application state or logic exists in JS, and no
browser API exists in SDK MoonBit code.

The JS host (`hosts/web/passport-host.js`, `hosts/web/pcm-worklet.js`,
`hosts/web/index.html`) owns:

- Instantiation, the `passport` import object, and the one `_start` call.
- Frame pacing (rAF loop; 16 ms interval fallback in Node) and `now_us`
  delivery as BigInt.
- Keyboard translation to semantic button codes (ArrowUp/W = Up,
  ArrowDown/S = Down, Enter/Space = Ok) with FIFO queueing, auto-repeat
  filtering, and flush-before-frame ordering.
- RGB565 -> RGBA presentation of the frozen framebuffer (blit + putImageData)
  and integer CSS canvas scaling.
- Normalized-PCM playback: synchronous LE decode, ring scheduling,
  AudioWorklet/ScriptProcessor transport, master gain, mute, and the
  best-effort playback position.
- The optional PCM asset transport (fetch, raw-byte residency, bounded
  chunk refill, sample-exact loop, asset facts) — host configuration only,
  explicitly exclusive with the streamed `host_pcm_write` producer.
- Battery fixture (default 82; `?battery=NN` / `?battery=none` URL params)
  and the host-facts HUD.
- Boot validation (little-endian check, export surface, `fb_ptr`/`fb_len`)
  and the test surface (`window.__passportHost` / `createHost()`).

The MoonBit app (through the SDK packages, as exercised by
`src/fixture/**`) owns:

- **All** application state, logic, and frame content decisions.
- Rendering through the SDK `Canvas` (logical 120x160, RGB565 quantization).
- Input state semantics: raw wire codes become `@input.Button` values and
  `InputState` edges (`press`/`release`/`just_pressed`/`advance`); JS never
  decides what a button means to the app.
- Battery caching (`@battery.Battery` with explicit `refresh()` over the
  bridge `BatterySource`).
- PCM generation, clamping, staging, and chunking semantics (the bridge
  `PcmSink`); the host only decodes and schedules what it receives.
- Clock semantics: `HostBridge::advance(now_us)` is monotonic; derived
  `Clock::monotonic_ms` never rewinds (`src/hostabi/bridge.mbt`).

## Fixture proof (what is verified, and how)

`src/fixture` is the smallest main package that proves the boundary
end-to-end. Its frozen, deterministic contract:

- 8x8 block at (0,0)-(7,7) cycles `[0xF800, 0x07E0, 0x001F, 0xFFFF]`
  (red/green/blue/white) on `N % 4`; pixel (8,8) stays black (gap proof).
- Full-width 1px selection row at `y = 20 + sel*8` (0..=9, start 0), yellow;
  Up/Down move it via `InputState` just-pressed edges (floor 0, cap 9).
- Mute flag block at (112,0)-(119,7): white when muted, cyan when not; Ok
  toggles and mirrors the flag with `host_set_muted`.
- Volume bar: columns 118..119, `160*70/100 = 112` rows green (fixture calls
  `host_set_volume(70)` once at init).
- Battery text at (4,150) in white from the bridge-backed cache (fixture 82
  -> `"82%"`); region stays black when the source reports `None`.
- Background black; playback position is never drawn.
- PCM: exactly 266 samples per frame from the frozen waveform above.

### How to run the verification suite

```sh
# from the repository root
moon build --target wasm --release        # fixture app.wasm (release)
moon build --target wasm                  # fixture app.wasm (debug; the suite pins both profiles)
node hosts/web/tools/gen-test-pcm.mjs     # once, creates the committed asset
node hosts/web/tools/make-bundle.mjs      # assemble _build/passport-bundle
node hosts/web/test/run-tests.mjs         # all suites
# local escape hatch: node hosts/web/test/run-tests.mjs --skip-browser
```

The frozen test asset `hosts/web/assets/test.pcm` is 8000 bytes (first 4000
samples = 0.25 s at 16000 Hz, PCM16 LE mono), byte-identical on
regeneration (`hosts/web/tools/gen-test-pcm.mjs`).

`run-tests.mjs` and `make-bundle.mjs` resolve all their inputs (fixture wasm
artifacts, PCM asset, bundle output) relative to the repository root, so run
them from the repository root. `run-tests.mjs` checks the built artifacts and
**exits 2 when the fixture wasm artifacts are missing** (printing the exact
`moon build` commands) — a missing prerequisite is never silently skipped —
and exits 1 if any suite fails.

### Continuous integration (wasm-host job)

`.github/workflows/ci.yml` runs a dedicated `wasm-host` job on
`ubuntu-latest`, alongside the native/js job:

1. `moon check --target wasm --output-json` and
   `moon test --target wasm --output-json`.
2. Build the fixture in **both** profiles (`--release`, then debug) and
   record the artifact paths.
3. `node hosts/web/tools/gen-test-pcm.mjs`.
4. Install the pinned browser:
   `npx -y playwright@1.63.0 install chromium --with-deps` (one pinned
   version so the suite's cache scan resolves exactly it).
5. `node hosts/web/test/run-tests.mjs` — **no skip flags**: both browser
   suites must run, through the playwright path. Exit code 2 means the
   fixture wasm artifacts were missing; exit 1 means a suite failed.

The browser gate contract: on the playwright path both probes enable **real
audio** (no fake context), and the suite requires the normalized-PCM host
path proven end to end — wasm pushed PCM through `host_pcm_write`
(`pcmStats` bytes/calls > 0), a real audio transport exists (worklet or
script), and the render side actually consumed samples (consumed > 0, i.e.
audio proof `full`). The PCM asset browser suite additionally requires the
AudioWorklet transport itself on the playwright path, the seam-exact
first-chunk checksum against the node-side PCM16 decode, consumption past
two full asset loops (loop refill), continued wasm/canvas frames during
audio, and a position that keeps advancing while muted. CI never skips the
browser suites.

### Browser coverage (what each launch path proves)

The browser suite tries, in order (details in `hosts/web/test/README.md`):

1. **playwright** — the CI mechanism: pinned chromium against the
   http-served `hosts/web/test/browser-probe.html` probe page (real
   `fetch("app.wasm")` loading path). Full audio proof is **required** here
   (consumed > 0, `audioProof: "full"`).
2. **chrome-headless-shell + http** — local fallback against the same probe
   page.
3. **chrome-headless-shell + self-contained `data:` URL** — environment
   fallback for browsers that cannot complete plain http navigation: the
   unmodified `passport-host.js` is blob-imported and the bundle's
   `app.wasm` is passed inline; the probe logic and assertions are
   identical, only the loading path differs.

On every successful browser path the suite asserts display/input equality
against a node-side golden instance plus the PCM crossing (`pcmStats > 0`)
and a real audio transport. Only on the non-playwright fallbacks, if sample
consumption stays 0 after a bounded wait, the suite passes with a loud
`audioProof: "ingest-only"` marker line instead of failing — a documented
environmental degradation that is never seen on the CI (playwright) path.

## Consumability (what a downstream project needs)

To build a wasm app against this SDK and run it in the web host, a downstream
project needs:

1. An **app main package** like `src/fixture`: a wasm-targeted executable
   whose `moon.pkg` sets `options(link: { "wasm": { "exports": [...six
   passport_* symbols...], "heap-start-address": 65536 } })` and
   `supported_targets = "wasm"` (text `moon.pkg` syntax; `moon fmt`
   canonicalizes `options("is-main": true)` to
   `pkgtype(kind: "executable")`, and exported wrappers must be `pub fn`).
2. The built artifact: `moon build --target wasm --release` produces the
   app wasm (fixture path: `_build/wasm/release/build/fixture/fixture.wasm`).
3. The **host assets**: `hosts/web/passport-host.js`,
   `hosts/web/pcm-worklet.js`, `hosts/web/index.html`, served over http(s)
   in a bundle directory containing `app.wasm`, `sounds.bank` and any
   declared ordinary assets under `<bundle>/assets/`
   (`hosts/web/README.md` "Bundle directory contract"; `file://` does not
   work). `hosts/web/tools/make-bundle.mjs` assembles that bundle (default
   `_build/passport-bundle` at the repository root) from the release wasm
   and the test asset. Downstream projects consume these files from the
   published `colmugx/ai-passport` package the CLI resolves for them
   (`.mooncakes/colmugx/ai-passport/hosts/web/`) — never from GitHub.

   `sounds.bank` is the shared APSB v1 resource format documented in
   `SOUND_BANK.md`. This ABI v0 Host still uses the legacy PCM paths and does
   not consume the bank until the sound-runtime cutover.

## Limitations

- **Big-endian platforms are rejected at host boot** (little-endian check);
  ABI v0 framebuffer and PCM are LE by ISA guarantee.
- **PCM pacing**: the fixture pushes a fixed 266 samples per rAF tick —
  deterministic, but not audio-clock paced.
- **Playback position is host best-effort**: consumption reports arrive
  roughly every 32 ms and the position is interpolated from
  `AudioContext.currentTime` between them, so it is optimistic during
  underrun. Formula in `hosts/web/README.md` ("Position formula").
- **Unused wasm imports are dead-code-eliminated per build profile**: the
  fixture keeps `host_playback_pos_us` in the import table via a write-only
  probe store in `main` (`src/fixture/state.mbt`; a bare `let _ =` binding
  dies in debug).
- **Sample rate hint**: `AudioContext` is constructed at 16000 Hz; engines
  that ignore the hint play at the wrong pitch (no host-side resampler).
- **ScriptProcessor fallback** exists where AudioWorklet is unavailable; it
  is deprecated, main-thread, and a compatibility path only.
- The host is served over http(s) only — ES modules, `fetch("app.wasm")`,
  and AudioWorklet `addModule` all require it (`hosts/web/README.md`).
