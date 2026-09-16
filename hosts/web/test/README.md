# Wasm-host integration tests, PCM asset, and bundle tooling (W4 / R1.2)

Node-side integration suites for the SDK Wasm host backend (R1 Wave C). They
pin the FROZEN contracts ("ABI v0 contract": framebuffer ptr 4096 / len 38400,
PCM staging ptr 42496; "Fixture contract": the frozen square wave) against the
real built artifacts:

- `../passport-host.js` — the host module under test (suites 4-7 and the
  pcm-asset suites import it directly; no DOM needed).
- `_build/wasm/{release,debug}/build/fixture/fixture.wasm` — the fixture app
  the host boots (suites 2-3 instantiate it with stub imports; suite 9 runs it
  in a real browser).
- `assets/test.pcm` — the committed normalized-PCM test asset (0.25 s of the
  frozen integer square wave, PCM16 LE mono 16000 Hz, 8000 bytes). Also the
  HTTP-served asset of the PCM asset browser suite.
- `minimal-wasm.mjs` — deterministic emitter for the minimal no-import wasm
  module used by the PCM asset suites (satisfies the ABI v0 export surface,
  imports nothing, so the host boots it in asset mode).
- `pcm-asset-suites.mjs` — the node-side PCM asset suites (10-16), registered
  into `run-tests.mjs`.

There is no `package.json`, no `node_modules`, and no CDN dependency: plain
node (v24) plus an already-cached chromium (playwright's browser registry or
the chrome-headless-shell cache) are enough; the playwright package itself is
resolved from a prior `npx playwright@1.63.0 ...` run when present.

## Run everything

```sh
# 1. Build the fixture artifacts (both profiles) from the repo root
moon build --target wasm
moon build --target wasm --release

# 2. Generate the PCM test asset (deterministic; idempotent)
node hosts/web/tools/gen-test-pcm.mjs

# 3. Assemble a test bundle (default outdir: _build/passport-bundle)
node hosts/web/tools/make-bundle.mjs            # or: ... <outdir>

# 4. Run all suites; exits non-zero on any failure
node hosts/web/test/run-tests.mjs               # add --skip-browser to skip the browser suites
```

`run-tests.mjs` checks 1-2 and auto-generates the asset (via 2) if missing,
printing what it does; it never builds or downloads anything else. Execution
order follows registration: suites 1-8, the pcm-asset node suites (10-17),
then the two browser suites (9 and 18) last.

## Suites

| # | Suite | What it pins |
|---|---|---|
| 1 | `pcm-asset` | `assets/test.pcm` is exactly the first 4000 samples of `sample(n) = ((n >> 4) & 1) == 1 ? -4000 : 4000`. |
| 2 | `abi-golden:release` | Release fixture wasm vs the frozen contracts: exact export/import surfaces, `fb_ptr=4096`/`fb_len=38400`, exact RGB565 pixels for N=0..7 plus input scenarios (Down/Up movement, floor 0, cap 9, unknown button codes, Ok mute toggles), dirty/consume protocol, `host_set_volume`/`host_set_muted` call logs, 266 PCM samples/frame with the cumulative frozen waveform, battery=82 text vs battery=-1 black region. |
| 3 | `abi-golden:debug` | Debug artifact keeps the same export/import surface (all five `passport.host_*`), geometry, pixels, and PCM behavior. |
| 4 | `host-module: lifecycle` | `createHost()` under node: auto-boot DOM-guarded, frameCount/lastNowUs, queueInput reaches wasm (pixel effect), full-framebuffer RGBA round-trip against the exported `rgb565ToRgba8888`, canvas-less audio kind, playback-position seam, pcmStats basics. |
| 5 | `host-module: audio seams` | `pcmStats` counts only the wasm import path; `feedNormalizedPcm` shares the decode+queue path without touching stats; ScriptProcessor pull emits decoded Float32 and sets the position snapshot; position formula `round((consumed + max(0, now - snapshotTime) * 16000) * 1e6/16000)`; out-of-range `host_pcm_write` throws but still counts; volume/mute clamping. |
| 6 | `host-module: canvas-less` | No canvas: dirty/consume protocol still runs (`tick()` returns `presented: true`); `dispose()` stops the interval loop and freezes the host; start/dispose idempotence. |
| 7 | `host-module: memory growth` | `memory.grow(1)` detaches the old framebuffer buffer; `getFramebufferView()` re-binds to the grown memory; content and the app survive growth. |
| 8 | `bundle` | `make-bundle.mjs` copies the release wasm and the asset byte-identically (temp outdir and the default `_build/passport-bundle`); refuses with the exact `moon build` command when the wasm is missing. |
| 10 | `pcm-asset: minimal wasm module` | `minimal-wasm.mjs` emits a deterministic module importing NOTHING that satisfies the ABI v0 export surface (fb 4096/38400, always-dirty frames, `passport_frame` stores low16(now_us) at pixel 0) and boots through `createHost` in asset mode. |
| 11 | `pcm-asset: strict input, non-blocking load` | Exact PCM16 LE -> Float32 (/32768) decode sample-for-sample; odd/empty artifacts and HTTP 404 reject `waitForAudioAsset` without ever blocking ticks; a deliberately slow fetch lets 5 frames run first; config validation (url+bytes, pcmLoop without source, non-string url); neutral asset facts on non-asset hosts. |
| 12 | `pcm-asset: bounded refill` | 40000-sample asset through ScriptProcessor pulls: every output sample equals the frozen square wave at its global index (cursor advances exactly); decode chunks never exceed 3200 samples (no whole-track Float32 — `maxChunkSamples`); pending queue bounded (`peakPendingSamples`); decode is incremental; consumption crosses >= 3 passes. |
| 13 | `pcm-asset: sample-exact loop` | `[A B C]` looping must emit `A B C A B C ...` for 2+ full pull buffers with NO missing/duplicated boundary sample; `eof` never set. |
| 14 | `pcm-asset: non-loop EOF` | `[A B C]` non-looping plays exactly A B C then silence, forever: EOF sets, cursor parks at the sample count, no further decode, position freezes at exactly the asset length (188 µs). |
| 15 | `pcm-asset: mute/volume` | Mute forces gain 0 without moving the cursor; position/loops/decode continue while muted; volume while muted keeps gain 0 and never alters the cursor; unmute maps volume -> gain; position monotonic across toggles. |
| 16 | `pcm-asset: suspended AudioContext` | With the context suspended: the asset loads, initial refill happens, 10 frames present, position stays 0n; after the simulated unlock, audio flows through the same transport and frames still run. |
| 17 | `pcm-asset: exclusivity` | The real fixture wasm (imports `host_pcm_write`) + asset config fails loudly at `createHost` naming both modes; on asset hosts `feedNormalizedPcm`/the default import throw; the minimal module without asset options stays a plain streamed host. |
| 9 | `browser` | Exact RGB565 output and the full normalized-PCM host path in a real browser: a real chromium boots the bundle, drives the same deterministic frame/input sequence as a node-side golden instance, and the canvas `getImageData` FNV-1a checksum must equal the node-side `rgb565ToRgba8888`-derived expectation (plus framebuffer checksum equality and frame-count sanity). Additionally, with REAL audio enabled, wasm `host_pcm_write` must push PCM (`pcmCalls`/`pcmBytes`), the audio transport must be worklet or script, samples must be handed to the transport (`audioFilled`), and on the playwright path the render side must actually consume them (`audioConsumed`, `audioProof: "full"`). |
| 18 | `browser pcm-asset` | The PCM asset transport in a real browser: the minimal no-import wasm boots an asset host that fetches `assets/test.pcm` over HTTP, decodes bounded chunks through the SAME AudioWorklet transport (first posted chunk byte-equals the node-side PCM16 decode), consumes past 2 full asset loops (loop refill), keeps presenting wasm/canvas frames while audio runs, and muting does not stop the playback position. On the playwright (CI) path the AudioWorklet transport itself is required. |

## Browser suite (9) requirements and fallbacks

The suite tries, in order:

1. **playwright** — `import("playwright")`, then the npx cache
   (`~/.npm/_npx/*/node_modules/playwright` on darwin/linux, respecting
   `npm_config_cache`; `%LocalAppData%\npm-cache\_npx` on win32). Use
   whichever resolves; the pinned browser build must be in playwright's
   browser registry (`PLAYWRIGHT_BROWSERS_PATH` if set to a real path, else
   `~/Library/Caches/ms-playwright/` on macOS, `~/.cache/ms-playwright/` on
   linux, `%LocalAppData%\ms-playwright\` on Windows). CI uses this path:
   `npx -y playwright@1.63.0 install chromium` puts both the package in the
   npx cache and the pinned chromium build in the registry above.
2. **chrome-headless-shell + http** — the cached
   `chromium_headless_shell-*/chrome-headless-shell` binary with
   `--dump-dom --virtual-time-budget` against `test/browser-probe.html`,
   served by a throwaway node http server (hosts/web/ + the bundle dir).
3. **chrome-headless-shell + self-contained data: URL** — environment
   fallback for browsers that cannot complete plain http navigations: the
   unmodified `passport-host.js` source is blob-imported, the worklet source
   is delivered as a blob URL (`workletUrl`; a data: page has an opaque
   origin and no server, so the default worklet location cannot be resolved),
   and the bundle's `app.wasm` is passed inline via `options.wasmBytes`.
   Identical probe logic and assertions; only the loading path differs. The
   chosen path is printed in the suite output. The data: probe is retried up
   to 3 times with a 1.5 s pause between attempts because intermittent
   headless-shell data:-URL navigation has been observed on macOS, while the
   known-dead http probe is attempted only once per run since each attempt
   burns its full timeout.

### The audio proof

Both probe pages (http and data:) construct the host with REAL audio — no
`audioContextFactory` override — so `createHost` builds the real
`AudioContext` at 16000 Hz and prefers the AudioWorklet transport
(`/pcm-worklet.js` on the http path, a blob URL on the data: path; if
`addModule` fails there, the host's documented ScriptProcessor fallback is
used and the payload records it). Every launcher passes
`--autoplay-policy=no-user-gesture-required` so the context starts running
without a user gesture; the probe also calls the host's `resumeAudio()` seam
(again inside its wait loop) in case the context starts suspended.

After the deterministic tick sequence, the page waits — bounded inside the
page: until consumption is observed, 3 s pass on the AudioContext's real-time
clock, 10 s of wall time elapse, or audio is provably absent — then writes
the payload with these audio fields:

- `audioKind` — `"worklet"` | `"script"` (worklet preferred; `"script"` on the
  data: path is acceptable because a data: page cannot fetch a worklet file
  from a server — the worklet is delivered as a blob URL instead, and a
  refusal degrades to the documented ScriptProcessor fallback).
- `pcmCalls` / `pcmBytes` — `host.pcmStats`: wasm pushed normalized PCM
  through `host_pcm_write` in the real browser (6 calls / 3192 bytes for the
  6-frame probe sequence).
- `audioFilled` — samples handed toward the audio transport (worklet:
  `postMessage`ed chunks counted by wrapping the node's port; script: pulled
  samples). 1596 = 6 x 266 for the probe sequence.
- `audioConsumed` — cumulative samples the render side reports consuming
  (worklet port reports; script: the host's position snapshot after each
  pull).
- `audioWaitMs` — how long the bounded wait ran.
- `audioProof` — `"full"` when `audioConsumed > 0`, else `"ingest-only"`.

Node-side gates on every successful browser path: `status: "ok"`, all
display/input checks (frame/lastNowUs/fbLen/volume/selCheck/fbCrc/canvasCrc —
unchanged), `pcmCalls > 0 && pcmBytes > 0`, `audioKind` worklet-or-script,
`audioFilled > 0`. When the path is **playwright** (the CI mechanism),
`audioConsumed > 0` and `audioProof: "full"` are additionally REQUIRED — the
full host path is proven end to end. On the local chrome-headless-shell
FALLBACK only, if consumption stays 0 after the bounded wait the suite still
passes but prints

```
  browser fallback: audio render not verifiable in this environment (ingest-only)
```

and the payload carries `audioProof: "ingest-only"`. That line marks a
documented environmental degradation of a FALLBACK; it is never seen in CI.

`--skip-browser` (or `PASSPORT_SKIP_BROWSER=1`) skips the browser suites
entirely; the remaining suites are fully hermetic.

## Browser PCM asset suite (18)

`test/pcm-asset-probe.html` boots the host in PCM asset mode with the REAL
AudioContext: the app is the minimal no-import wasm (generated into the
throwaway bundle dir as `assets/minimal.wasm` — never committed), and the
asset is the committed `assets/test.pcm` served over HTTP by the same
throwaway server (new routes: `/assets/test.pcm`, `/assets/minimal.wasm`,
`/test/pcm-asset-probe.html`). The page then reports:

- `assetLoaded`/`assetSamples`/`assetDurationUs`/`assetLooping` — the
  fetched-asset facts (4000 samples, 250000 µs, looping).
- `firstChunkLen`/`firstChunkCrc` — length and FNV-1a of the FIRST Float32
  chunk observed through the wrapped worklet port. The wrapper installs the
  moment the asset resolves, so the very first 3200-sample chunk of the
  initial fill may already be gone; the observed chunk is therefore one of
  the seam-aligned spans of the looping stream (3200-sample span [0,3200) or
  the 800-sample loop-seam span [3200,4000) for the committed asset). The
  node side recomputes the checksums of exactly those spans from the raw
  `.pcm` bytes; equality proves the browser decoded through the PCM16 LE
  path (no MP3/WAV decoder can produce these bytes).
- `audioFilled`/`consumed`/`loops` — transport handoff, render-side
  consumption, and consumption-based loop count (the wait exits only after
  2.4x the 0.25 s asset, so >= 2 full loops are proven with report-lag
  margin).
- `framesDuring`/`presentedDuring` — wasm frames kept running AND presenting
  to the canvas while audio was active.
- `muted`/`posAtMuteUs`/`posEndUs` — the page muted partway (after 1600
  consumed) and the position still advanced: mute never stops the clock.
- `dropped === 0` — the worklet ring never overflowed.

The same three launch paths apply (playwright first; chrome-headless-shell
http then a self-contained `data:` variant as local fallbacks). The `data:`
variant is the SAME page with `window.__PCM_ASSET_PROBE_INLINE__` injected
before the module script (host blob import, worklet blob URL, wasm and PCM
bytes inline — exercising `pcmAssetBytes`). On the playwright (CI) path the
AudioWorklet transport itself is required (`audioKind === "worklet"`); the
shell fallbacks may degrade to ScriptProcessor with the documented
ingest-only marker, exactly like suite 9.

## Tools

- `tools/gen-test-pcm.mjs` — regenerates `assets/test.pcm`; byte-identical on
  every run (prints byte count + sha256). The asset is committed.
- `tools/make-bundle.mjs` — assembles the host-consumable bundle directory
  (`app.wasm` + `assets/test.pcm`) per `hosts/web/README.md`'s bundle
  contract. Test tooling only, not project scaffolding. Env override for
  tests: `PASSPORT_FIXTURE_WASM=<path>` substitutes the wasm source (used to
  exercise the refusal path).
