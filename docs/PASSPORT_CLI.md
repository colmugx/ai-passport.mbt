# The passport CLI and the Host contract (R4A1)

> **Status: implemented for the next release, unpublished.** The release unit
> remains the whole `colmugx/ai-passport` Mooncakes module: the SDK libraries,
> the Web Host assets, and the `passport` CLI are co-versioned — a downstream
> project never fetches host files from GitHub and never installs a separate
> CLI package. Publishing has deliberately NOT been run for this round.

## What a Host is

A **Host** is one explicitly supported and validated execution environment
for an AI Passport application. Host is the ONLY backend abstraction in this
SDK's public surface — there is no product, board, machine, or platform
vocabulary anywhere in the CLI or the host model. Registered Hosts this
release:

| Host id | Backend status |
|---|---|
| `web` | implemented (build + dev) |
| `folotoy-ai-passport` | implemented (device build; requires the ESP-IDF toolchain) |

Future Hosts (for example `zectrix-note4`) are added to the registry without
any change to the CLI grammar.

### Capability model

`src/hosts` defines the registry and one capability vocabulary, deliberately
split into two planes so hardware facts never impersonate SDK APIs:

- `sdk_exposed` — capabilities reachable **today** through public SDK
  application APIs (`Display`, `Input`, `AudioOutput`, `Battery`, `Clock` for
  both implemented Hosts).
- `hardware_known` — capabilities confirmed on the Host's real hardware or
  runtime, whether or not the SDK reaches them yet. The FoloToy AI Passport
  wearable is described factually (ESP32-C3, 8 MB flash, no PSRAM, ST7789P3
  240x320 RGB565 panel at the 120x160 logical framebuffer, Up/Down/Ok,
  normalized PCM16 LE mono 16000 Hz playback asset, audio output,
  **microphone (audio input)**, CW2017 battery gauge, Wi-Fi, Bluetooth LE,
  timers/monotonic clock). The microphone and network are hardware facts the
  SDK does not expose as application APIs.

Descriptors carry facts, never wiring-level configuration: no GPIO numbers,
no bus maps. `passport hosts` renders them deterministically, and the
rendering is pinned by tests.

## The CLI

The CLI is the executable package `src/cmd/passport` (package path
`cmd/passport`, wasm target only).

- **Local invocation (this release, from the SDK repository root):**

  ```sh
  moon run --target wasm src/cmd/passport <command> [options]
  # examples:
  moon run --target wasm src/cmd/passport -- --help
  moon run --target wasm src/cmd/passport hosts
  moon run --target wasm src/cmd/passport doctor --host web --project <dir>
  moon run --target wasm src/cmd/passport build --host web --project <dir>
  moon run --target wasm src/cmd/passport dev --host web --project <dir> --port 8000
  ```

  (`--` separates moon flags from CLI flags; the module's preferred target is
  native, so `--target wasm` is required.)

- **Published invocation (intended, after the next release is published):**

  ```sh
  moonx colmugx/ai-passport/cmd/passport hosts
  moonx colmugx/ai-passport/cmd/passport build --host web
  ```

  `moonx` runs the executable package's prebuilt wasm. This repository does
  not claim the unpublished ai-passport CLI path as release-proven until a
  release containing the executable has actually been published and tested.

### Commands

- `passport hosts` — deterministic registry listing with capabilities and
  backend status.
- `passport doctor --host web [--project <dir>]` — checks exactly what web
  work needs: moon toolchain, `passport.json` contract, entry package,
  resolvable SDK Web Host assets, python3 (the dev server). For a clean
  project, doctor runs `moon check` on the declared wasm entry so Moon can
  resolve/materialize its declared dependencies before Host assets are
  inspected. It never demands device tooling.
- `passport doctor --host folotoy-ai-passport [--project <dir>]` — checks
  exactly what a device build needs, reporting every failure without
  aborting early: the pinned moon toolchain
  (`moon 0.1.20260915 (2e1a46d 2026-09-15)`), `idf.py` reporting ESP-IDF
  v5.5.3 (source the matching `export.sh` first), the project contract with
  a `deviceEntry` package, the device entry package and its `moon.pkg`, the
  looping PCM music asset source, the resolvable SDK device Host assets, the
  `$MOON_HOME` runtime files against the Host's `moonbit-runtime.sha256`
  manifest, and the external FoloToy dependency — which checkout a build
  would use, whether it matches the pinned content manifest, or (when
  absent) where the build would clone the pinned revision. Doctor never
  downloads anything.
- `passport build --host web [--project <dir>]` — the complete generic web
  build: compiles only the project's declared entry package for wasm release,
  then assembles `.passport/web/`:

  ```text
  .passport/web/
    app.wasm             the built application (release)
    index.html           SDK-owned, byte-for-byte from the resolved SDK
    passport-host.js     SDK-owned
    pcm-worklet.js       SDK-owned
    assets/...           every asset declared by the project contract
  ```

  A stale `app.html` is removed. Unimplemented Hosts fail clearly; there is
  no silent fallback to web.
- `passport build --host folotoy-ai-passport [--project <dir>]` — the device
  build. Preconditions: the ESP-IDF v5.5.3 environment must be sourced
  (`export.sh`), and `$MOON_HOME` (default `~/.moon`) must hold the pinned
  MoonBit installation whose runtime files match the Host's
  `moonbit-runtime.sha256` manifest. The project's `passport.json` must
  declare a `deviceEntry` package and exactly one `pcmLoop: true` asset. The
  flow, in order:

  1. load and validate the project contract;
  2. refuse clearly when `deviceEntry` or the looping PCM asset is missing;
  3. resolve the SDK's `hosts/folotoy/ai-passport` implementation;
  4. materialize the device workspace
     `<project>/.passport/folotoy-ai-passport/` (host files copied
     copy-over — the idf `build/` tree stays incremental; the SDK's own
     `test/` tree and `README.md` are never copied);
  5. copy the looping PCM asset to `<workspace>/passport_music.pcm`;
  6. resolve the external FoloToy dependency — the contract's
     `hostDependencies` checkout when declared, else the CLI-managed clone
     of the single pinned revision under
     `.passport/deps/folotoy-ai-passport/<revision>/` — verify it against
     the Host's content manifest, log its path/revision/origin, and connect
     it via a generated `upstream.cmake` (upstream source is compiled in
     place, never copied into the SDK or the workspace);
  7. capture the device entry's generated C: the capture cc is copied into
     the workspace, injected into the entry package's `moon.pkg` for exactly
     one `moon build <deviceEntry> --target native --release` invocation
     (`MOON_CC_CAPTURE_DIR` + `MOONBIT_NEW_NATIVE=0`), and the original
     `moon.pkg` bytes are restored on success and failure alike — the
     project source tree is never left modified;
  8. verify the pinned toolchain (ESP-IDF v5.5.3, moon version, runtime
     manifest);
  9. `idf.py reconfigure` in the workspace and verify the device baselines
     in the effective `sdkconfig` (`CONFIG_FREERTOS_HZ=1000`, custom
     partition table `partitions.csv`);
  10. `idf.py build` and report the firmware path, size and app-partition
      margin (partition size `0x380000`).

  The workspace accumulates `<workspace>/build/` output; the project's
  source tree is untouched.
- `passport dev --host web [--project <dir>] [--port N]` — build, then serve
  `.passport/web/` with an unmodified `python3 -m http.server` bound to
  127.0.0.1, and print the final URL (Ctrl-C exits cleanly). Other Hosts are
  built, not served: `dev` is a Web Host command.

### Where the SDK host files come from

The CLI never reaches into MoonBit's private global dependency-cache layout.
Host files come from the same SDK source tree Moon resolved for the project:

1. the SDK checkout itself when the project IS `colmugx/ai-passport`;
2. otherwise the project's `.mooncakes/colmugx/ai-passport/` materialization.

Normal project operations (`moon check` / `moon build`) are responsible for
resolving declared dependencies. The CLI does not rely on the deprecated
no-argument `moon install` flow, does not guess a private global cache path,
and does not download Host files from GitHub.

## The project contract (`passport.json`)

Deliberately minimal (R4A1); a machine-readable `passport.json` at the
project root:

```json
{
  "entry": "main",
  "deviceEntry": "runtime_native",
  "assets": [
    { "source": "assets/tone.pcm", "bundlePath": "assets/tone.pcm", "pcmLoop": true }
  ],
  "hostDependencies": {
    "folotoy-ai-passport": { "path": "external/folotoy-ai-passport" }
  }
}
```

- `entry` (required) — the application wasm entry package path relative to
  the module source root; its moon.pkg exports the six `passport_*` symbols
  with `heap-start-address = 65536`.
- `deviceEntry` (optional) — the device entry package path relative to the
  module source root: the native foreign-library package a physical Host
  builds and links. Same path rules as `entry` (relative, forward slashes,
  no traversal). A device build requires it and fails clearly without it;
  web builds ignore it.
- `assets` (optional) — files to materialize into the bundle. `source` is
  project-relative, `bundlePath` is bundle-relative. `pcmLoop: true` marks
  the (single) Host audio asset and produces the generic entry URL
  parameters `?pcm=<bundlePath>&pcmLoop=1`; the host configuration stays
  exactly the SDK's own URL-parameter mechanism. For a device build, the
  `pcmLoop: true` asset's source is the firmware's music file (copied to
  `passport_music.pcm` in the device workspace), so a project must declare
  exactly one looping PCM asset to be device-buildable.
- `hostDependencies` (optional) — project-provided checkouts of external
  Host dependencies (third-party hardware code the SDK itself never
  carries). Each entry maps a registered host id to a `path` relative to
  the project root. A declared path is authoritative: the build fails
  clearly when no checkout exists there instead of downloading behind the
  project's back. Without an entry the CLI manages the dependency itself,
  cloning the Host's single pinned revision under
  `.passport/deps/<host-id>/<revision>/` (never a moving ref) and
  verifying the content against the Host's tracked manifest before use.

Contract paths are forward-slash relative paths. Absolute paths, traversal
components (`.` / `..`), duplicate bundle destinations, and attempts to
replace Host-owned files (`app.wasm`, `index.html`, `passport-host.js`,
`pcm-worklet.js`) are rejected before filesystem access.

The contract cannot express GPIO, ESP-IDF settings, frame rate, or anything
application-specific — later rounds extend it without renaming these fields.

## Application-generality gates

The CLI contains zero application semantics — it cannot know what the user's
application is. This is enforced, not hoped for:

- suite `cli: structural gates` (hosts/web/test/cli-fixture-suites.mjs) scans
  every `src/hosts`, `src/cli` and `src/cmd/passport` source file and fails
  on any user-facing backend synonym (product/board) and on any starter-app
  vocabulary (which must never appear in tooling);
- two downstream-style fixtures live under `hosts/web/test/fixtures/` as
  complete nested MoonBit modules depending on the published
  `colmugx/ai-passport` package: fixture A (no audio; plain entry URL) and
  fixture B (one looping PCM asset; `?pcm=&pcmLoop=1`). Doctor is run against
  a clean fixture so dependency resolution is exercised through `moon check`.
  The integration suites build both with the CLI and boot both in a real
  chromium through the SDK's own index.html: fixture A proves frames + input
  with no audio dependency; fixture B proves the http PCM fetch, sample-exact
  looping through the AudioWorklet, ring health and continued frame
  presentation.

## Scope-change record (R4A1)

Round R4A1 added, by direct round directive: the Host model/registry
(`src/hosts`), the passport CLI (`src/cmd/passport` + `src/cli`), the
`moonbitlang/async` module dependency (CLI process/fs support), the two CLI
fixtures under `hosts/web/test/fixtures/`, and the CLI suites in
`hosts/web/test/` (`browser-common.mjs`, `cli-fixture-suites.mjs`, run-tests
registration). `hosts/web/README.md` and `hosts/web/test/README.md` —
authored for earlier rounds but never committed (they shipped in the
published zips as untracked-but-not-ignored files, and committed docs
reference them) — are now tracked. No existing public API changed; ABI v0 is
unchanged. This hardening pass also trims repository-only test material from
the published archive with `.moonignore` while keeping the CLI and Web Host
runtime assets packaged.
