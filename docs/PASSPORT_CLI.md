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
| `folotoy-ai-passport` | registered, descriptor only — device build is not migrated yet (next wave) |

Future Hosts (for example `zectrix-note4`) are added to the registry without
any change to the CLI grammar.

### Capability model

`src/hosts` defines the registry and one capability vocabulary, deliberately
split into two planes so hardware facts never impersonate SDK APIs:

- `sdk_exposed` — capabilities reachable **today** through public SDK
  application APIs (`Display`, `Input`, `AudioOutput`, `Battery`, `Clock` for
  the web host).
- `hardware_known` — capabilities confirmed on the Host's real hardware or
  runtime, whether or not the SDK reaches them yet. The FoloToy AI Passport
  wearable is described factually (ESP32-C3, 8 MB flash, no PSRAM, ST7789P3
  240x320 RGB565 panel at the 120x160 logical framebuffer, Up/Down/Ok, audio
  output, **microphone (audio input)**, battery gauge, Wi-Fi, Bluetooth LE,
  timers/monotonic clock) while claiming **no** SDK application APIs until the
  device backend is migrated.

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
  inspected. It never demands device tooling. `--host folotoy-ai-passport`
  prints the factual descriptor and fails with `host "folotoy-ai-passport"
  device build is not migrated yet`.
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
- `passport dev --host web [--project <dir>] [--port N]` — build, then serve
  `.passport/web/` with an unmodified `python3 -m http.server` bound to
  127.0.0.1, and print the final URL (Ctrl-C exits cleanly).

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
  "assets": [
    { "source": "assets/tone.pcm", "bundlePath": "assets/tone.pcm", "pcmLoop": true }
  ]
}
```

- `entry` (required) — the application wasm entry package path relative to
  the module source root; its moon.pkg exports the six `passport_*` symbols
  with `heap-start-address = 65536`.
- `assets` (optional) — files to materialize into the bundle. `source` is
  project-relative, `bundlePath` is bundle-relative. `pcmLoop: true` marks
  the (single) Host audio asset and produces the generic entry URL
  parameters `?pcm=<bundlePath>&pcmLoop=1`; the host configuration stays
  exactly the SDK's own URL-parameter mechanism.

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
