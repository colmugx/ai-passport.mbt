# The passport CLI and the Host contract

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
  moon run --target wasm src/cmd/passport generate-sounds --project <dir> --output <source>/sounds/generated.mbt
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
  work needs: moon toolchain, `passport.toml` contract, entry package,
  resolvable SDK Web Host assets, python3 (the dev server). For a clean
  project, doctor runs `moon check` on the declared wasm entry so Moon can
  resolve/materialize its declared dependencies before Host assets are
  inspected. It validates every declared sound through the same compiler used
  by builds. It never demands device tooling.
- `passport doctor --host folotoy-ai-passport [--project <dir>]` — checks
  exactly what a device build needs, reporting every failure without
  aborting early: the pinned moon toolchain
  (`moon 0.1.20260915 (2e1a46d 2026-09-15)`), `idf.py` reporting ESP-IDF
  v5.5.3 (source the matching `export.sh` first), the project contract
  (a `deviceEntry` package for the legacy 0.0.5 layout, or a library
  application entry whose device adapter the build generates), the entry
  package and its `moon.pkg`, the shared sound resources/bank, the
  transitional looping PCM music asset source when one is declared (a project
  with no audio asset is a valid state), the resolvable SDK device Host assets, the
  `$MOON_HOME` runtime files against the Host's `moonbit-runtime.sha256`
  manifest, and the external FoloToy dependency — which checkout a build
  would use, whether it matches the pinned content manifest, or (when
  absent) where the build would clone the pinned revision. Doctor never
  downloads anything.
- `passport generate-sounds --project <dir> --output <path>` — the narrow
  generator invoked by the application's Moon `rule` / `dev_build`. The only
  accepted output is `<source-root>/sounds/generated.mbt` (Moon may prefix it
  with `./`). It compiles ordered metadata into a typed enum implementing
  `@audio.Sound`; it does not read PCM payloads or build a bank. Normal Host
  builds use the same metadata compiler and additionally validate PCM bytes.
- `passport build --host web [--project <dir>]` — the complete generic web
  build: compiles only the project's declared entry package for wasm release,
  then assembles `.passport/web/`:

  ```text
  .passport/web/
    app.wasm             the built application (release)
    index.html           SDK-owned, byte-for-byte from the resolved SDK
    passport-host.js     SDK-owned
    pcm-worklet.js       SDK-owned
    sounds.bank          deterministic APSB v1 bank (valid empty bank when no sounds)
    assets/...           every asset declared by the project contract
  ```

  A stale `app.html` is removed. Unimplemented Hosts fail clearly; there is
  no silent fallback to web.
- `passport build --host folotoy-ai-passport [--project <dir>]` — the device
  build. Preconditions: the ESP-IDF v5.5.3 environment must be sourced
  (`export.sh`), and `$MOON_HOME` (default `~/.moon`) must hold the pinned
  MoonBit installation whose runtime files match the Host's
  `moonbit-runtime.sha256` manifest. The project must either declare a
  `deviceEntry` package (the legacy 0.0.5 layout) or use the single-entry
  application contract, whose FoloToy entry adapter the CLI generates
  (a legacy executable entry without `deviceEntry` is refused); a
  `pcmLoop: true` asset is optional (at most one). The flow, in order:

  1. load and validate the project contract and resolve the device entry:
     the declared `deviceEntry` package, or the generated
     `passport-generated/folotoy-ai-passport` adapter for a single-entry
     application;
  2. refuse clearly when neither applies or a declared looping PCM asset is
     missing;
  3. resolve the SDK's `hosts/folotoy/ai-passport` implementation;
  4. validate every `[[sounds]]` source and compile the deterministic APSB v1
     bank before modifying the existing workspace;
  5. refresh the device workspace
     `<project>/.passport/folotoy-ai-passport/`: remove stale Host/source
     and generated entries, preserve only the incremental ESP-IDF state
     (`build/`, `managed_components/`, `sdkconfig`, `sdkconfig.old`),
     then copy the current SDK Host files; the SDK's own `test/` tree and
     `README.md` are never copied;
  6. write the same compiler output to `<workspace>/sounds.bank`, then copy
     the transitional looping PCM asset to `<workspace>/passport_music.pcm`
     when declared; without the latter the legacy runtime embeds no
     application music;
  7. resolve the external FoloToy dependency — the contract's
     `hostDependencies` checkout when declared, else the CLI-managed clone
     of the single pinned revision under
     `.passport/deps/folotoy-ai-passport/<revision>/` — verify it against
     the Host's content manifest, log its path/revision/origin, and connect
     it via a generated `upstream.cmake` (upstream source is compiled in
     place, never copied into the SDK or the workspace);
  8. capture the device entry's generated C: the capture cc is copied into
     the workspace, injected into the entry package's `moon.pkg` for exactly
     one `moon build <deviceEntry> --target native --release` invocation
     (`MOON_CC_CAPTURE_DIR` + `MOONBIT_NEW_NATIVE=0`), and the original
     `moon.pkg` bytes are restored on success and failure alike — the
     project source tree is never left modified;
  9. verify the pinned toolchain (ESP-IDF v5.5.3, moon version, runtime
     manifest);
  10. `idf.py reconfigure` in the workspace and verify the device baselines
     in the effective `sdkconfig` (`CONFIG_FREERTOS_HZ=1000`, custom
     partition table `partitions.csv`);
  11. `idf.py build` and report the firmware path, size and app-partition
      margin (partition size `0x380000`).

  The workspace keeps `build/`, `managed_components/`, `sdkconfig` and
  `sdkconfig.old` across builds for incremental ESP-IDF work; Host sources
  are refreshed from the current SDK on every build so removed/renamed files
  cannot survive. The project's source tree is untouched.
- `passport dev --host web [--project <dir>] [--port N]` — build, then serve
  `.passport/web/` with an unmodified `python3 -m http.server` bound to
  127.0.0.1, and print the final URL (Ctrl-C exits cleanly). Other Hosts are
  built, not served: `dev` is a Web Host command.

### Where the SDK host files come from

Project loading treats `moon.mod`'s top-level `name` and optional `source`
as strict quoted scalar metadata: normal whitespace and trailing line comments
are accepted, while duplicate declarations or malformed values are rejected
before generated-output cleanup.

The CLI never reaches into MoonBit's private global dependency-cache layout.
Host files come from the same SDK source tree Moon resolved for the project:

1. the SDK checkout itself when the project IS `colmugx/ai-passport`;
2. otherwise the project's `.mooncakes/colmugx/ai-passport/` materialization.

Normal project operations (`moon check` / `moon build`) are responsible for
resolving declared dependencies. The CLI does not rely on the deprecated
no-argument `moon install` flow, does not guess a private global cache path,
and does not download Host files from GitHub.

## The project contract (`passport.toml`)

Deliberately minimal; a machine-readable `passport.toml` at the project
root. The current contract has ONE application entry — the same application
package is the semantic source for every Host:

```toml
entry = "app"

[[assets]]
source = "assets/tone.pcm"
bundlePath = "assets/tone.pcm"
pcmLoop = true

[[sounds]]
name = "jump"
source = "assets/jump.pcm"

[hostDependencies."folotoy-ai-passport"]
path = "external/folotoy-ai-passport"
```

- `entry` (required) — the application package path relative to the module
  source root. A normal project keeps `source = "src"` in `moon.mod`, so
  `entry = "app"` names the package at `src/app`; nothing about the
  project's own layout or imports has to change for the CLI. The package
  implements the SDK application contract
  (`colmugx/ai-passport/application`): a type implementing
  `Application` exposed through one `pub fn passport_main() -> &Application`
  function. Every platform detail — Wasm ABI exports, C ABI exports,
  bridges, wiring, startup glue — lives in SDK runtime code and in the Host
  entry adapters the CLI generates; the
  application package must not import Host implementation packages.
- `assets` (optional) — files to materialize into the bundle. `source` is
  project-relative, `bundlePath` is bundle-relative. `pcmLoop: true` marks
  the (single) Host audio asset and produces the generic entry URL
  parameters `?pcm=<bundlePath>&pcmLoop=1`; the host configuration stays
  exactly the SDK's own URL-parameter mechanism. For a device build, the
  `pcmLoop: true` asset's source is the firmware's music file (copied to
  `passport_music.pcm` in the device workspace). Declaring no audio asset is
  a valid application: the device firmware then embeds no music and the Host
  reports playback unavailable, while the audio hardware capability stays.
- `sounds` (optional) — ordered preprocessed PCM resources, separate from
  ordinary assets. Each table contains only `name` and project-relative
  `source`; playback behavior such as loop, autoplay, volume and channel is
  rejected here. Names must produce distinct MoonBit constructor symbols.
  Sources must be non-empty `.pcm` files with an even byte length. Their
  input contract is signed PCM16 little-endian, mono, 16000 Hz and headerless;
  the CLI cannot infer sample rate or channel count from headerless bytes.
  Every build emits a deterministic `sounds.bank`, including a valid empty
  bank when the list is absent. The application-owned `sounds/moon.pkg` uses
  Moon `rule` / `dev_build` to invoke `passport generate-sounds`, producing
  `@sounds.Name` constructors before IDE checks and builds. See
  `SOUND_BANK.md` for the exact package configuration.
- `hostDependencies` (optional) — project-provided checkouts of external
  Host dependencies (third-party hardware code the SDK itself never
  carries). Each entry maps a registered host id to a `path` relative to the
  project root. A declared path is authoritative: the build fails clearly
  when no checkout exists there instead of downloading behind the
  project's back. Without an entry the CLI manages the dependency itself,
  cloning the Host's single pinned revision under
  `.passport/deps/<host-id>/<revision>/` (never a moving ref) and
  verifying the content against the Host's tracked manifest before use.

Contract paths are forward-slash relative paths. Absolute paths, traversal
components (`.` / `..`), duplicate bundle destinations, and attempts to
replace Host-owned files (`app.wasm`, `index.html`, `passport-host.js`,
`pcm-worklet.js`, `sounds.bank`) are rejected before filesystem access.

The contract cannot express GPIO, ESP-IDF settings, frame rate, or anything
application-specific — later rounds extend it without renaming these fields.

### Generated Host entries (`<source-root>/passport-generated/`)

A `passport build` regenerates the target-specific entry adapter packages
under the module source root's `passport-generated/` tree (for a project
with `source = "src"` that is `src/passport-generated/`) — build output the
CLI owns completely (wiped and regenerated by every build, never edited,
gitignored by downstream projects):

- `passport-generated/web` — the Wasm executable exporting the six frozen
  ABI v0 `passport_*` symbols, wrapping the application in the SDK Web
  runtime;
- `passport-generated/folotoy-ai-passport` — the native foreign library
  exporting the eight `ai_passport_mbt_*` C symbols `app_main` calls,
  wrapping the application in the SDK FoloToy runtime (including its
  measured presentation-lead calibration).

The tree must be a visible directory under the module source root because
moon discovers only packages there — a generated entry has to be an
in-module package to import the application entry — and moon skips
dot-directories entirely, so it cannot hide under `.passport/`. Downstream
projects ignore it with one `.gitignore` line: `passport-generated/`.

### Legacy entry layout (published 0.0.5 projects)

Projects published against 0.0.5 keep working unchanged: an `entry` whose
package is itself a Wasm executable (the old runtime package exporting the
`passport_*` symbols) builds directly, and `deviceEntry` (optional for
them) names the native foreign-library package a physical Host builds. The
CLI detects the legacy shape from the entry package's `moon.pkg` (an
executable entry is never an application-contract entry) and keeps the two
layouts strictly separate; new projects must not use `deviceEntry`. A
legacy executable entry without a `deviceEntry` is still refused by device
builds with the 0.0.5 error.

## Application-generality gates

The CLI contains zero application semantics — it cannot know what the user's
application is. This is enforced, not hoped for:

- suite `cli: structural gates` (hosts/web/test/cli-fixture-suites.mjs) scans
  every `src/hosts`, `src/cli`, `src/cmd/passport`, `src/application` and
  `src/runtime` source file and fails on any user-facing backend synonym
  (product/board) and on any starter-app vocabulary (which must never appear
  in tooling);
- downstream-style fixtures live under `hosts/web/test/fixtures/` as
  complete nested MoonBit modules depending on published
  `colmugx/ai-passport` versions: fixture A covers a no-audio legacy entry
  with a plain entry URL, while fixture B covers one looping PCM asset and
  `?pcm=&pcmLoop=1`. Doctor is run against a clean fixture so dependency
  resolution is exercised through `moon check`. The integration suites
  build those fixtures with the CLI and boot them in a real chromium through
  the SDK's own index.html: fixture A proves frames + input with no audio
  dependency; fixture B proves the HTTP PCM fetch, sample-exact looping
  through the AudioWorklet, ring health and continued frame presentation.
  Current unpublished CLI behavior is exercised with temporary projects
  constructed directly from this checkout rather than dependency overlays.
