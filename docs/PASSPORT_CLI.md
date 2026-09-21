# Passport CLI and Host contract

The `passport` executable, SDK packages, and Host assets are one co-versioned
release. Host is the only backend abstraction. The current registered Hosts
are `web` and `folotoy-ai-passport`; both run the same application semantics
and consume the same APSB v1 sound-bank bytes.

## Commands

From this repository:

```sh
moon run --target wasm src/cmd/passport hosts
moon run --target wasm src/cmd/passport doctor --host web --project <dir>
moon run --target wasm src/cmd/passport generate-sounds <input> <output>
moon run --target wasm src/cmd/passport build --host web --project <dir>
moon run --target wasm src/cmd/passport build --host folotoy-ai-passport --project <dir>
moon run --target wasm src/cmd/passport dev --host web --project <dir>
```

`hosts` prints the deterministic Host registry. `doctor` validates the exact
project, sound, SDK-asset, and toolchain prerequisites for its Host and reports
all detected failures. `build` creates the selected Host workspace. `dev` is a
Web-only build plus a loopback HTTP server.

`generate-sounds INPUT OUTPUT` is the narrow Moon Rule entry point. It must run
from the project root, requires `INPUT` to resolve to that root's
`passport.toml`, and writes only the requested `.mbt` output inside the module
source tree. It does not choose the generated package name or filename.

## Project contract

`passport.toml` sits at the MoonBit module root:

```toml
entry = "app"

[[assets]]
source = "assets/map.bin"
bundlePath = "assets/map.bin"

[[sounds]]
name = "forest_walk"
source = "assets/forest_walk.pcm"

[[sounds]]
name = "hit"
source = "assets/hit.pcm"

[hostDependencies."folotoy-ai-passport"]
path = "external/folotoy-ai-passport"
```

- `entry` is the application package relative to the module source root. A
  normal project with `source = "src"` places it at `src/app`.
- `assets` are ordinary bundle files. They have only `source` and
  `bundlePath`; they carry no sound or playback semantics.
- `sounds` are ordered PCM resources. They have only `name` and `source`.
  Names must map to unique MoonBit constructors. Sources must be contained
  project-relative `.pcm` files, non-empty, and even-sized. The developer's
  preprocessing pipeline guarantees signed PCM16 little-endian, mono,
  16000 Hz, because headerless PCM cannot prove rate or channel count.
- `hostDependencies` optionally points at a project-owned external Host
  dependency checkout. If absent, the CLI uses its pinned clone under the
  project's `.passport/deps/` tree. Third-party hardware source is never
  copied into this SDK.

Unknown fields fail. In particular, loop, autoplay, volume, channel, and the
removed PCM-loop asset flag are not resource metadata. Looping is selected by
each `@audio.play` call.

All contract paths use forward-slash relative syntax. Absolute paths,
traversal, duplicate destinations, and attempts to replace Host-owned files
are rejected before output is modified.

## Typed Sound package

The application owns the package name and generated filename. A package can
import `colmugx/ai-passport/audio` and declare:

```moonbit
rule(
  name: "passport-sounds",
  command: "passport generate-sounds $input $output",
)

dev_build(
  rule: "passport-sounds",
  input: "../../passport.toml",
  output: "generated.mbt",
)
```

Import that package as `@sounds` and use constructors such as
`@sounds.ForestWalk` and `@sounds.Hit`. Moon runs the Rule for IDE checks,
builds, and tests. Rule generation and Host builds call the same sound metadata
compiler, so symbol order and APSB Sound IDs cannot drift. See
`SOUND_BANK.md` for the binary format and exact validation contract.

## Web build

`passport build --host web` compiles the application for release Wasm and
atomically refreshes:

```text
.passport/web/
  app.wasm
  index.html
  passport-host.js
  sound-worklet.js
  sounds.bank
  assets/...
```

The URL is simply `/index.html`; audio resources are never configured by URL.
A no-sound project still receives a valid empty bank. A stale build directory
is replaced so removed assets cannot survive.

## FoloToy device build

`passport build --host folotoy-ai-passport` requires a MoonBit installation and
the pinned ESP-IDF toolchain described in the Host README. Before touching the workspace
it validates every sound and compiles the APSB bank. It then refreshes
`<project>/.passport/folotoy-ai-passport/`, preserving only incremental ESP-IDF
state (`build/`, `managed_components/`, `sdkconfig`, and `sdkconfig.old`), and
writes `sounds.bank` at the workspace root.

The CLI generates or resolves the device application adapter, captures its
MoonBit native C without leaving the source package modified, verifies the
external FoloToy dependency, writes `upstream.cmake`, and
runs `idf.py reconfigure` followed by `idf.py build`. The device Host embeds
the same bank bytes in flash and its `sound_player` owns codec output and the
fixed playback slots. The build never flashes a device.

Published 0.0.5 projects may still declare a separate `deviceEntry`; this is
an application-entry layout compatibility path, not an audio compatibility
path. The removed single-PCM asset, URL, workspace, and Host ABI models have no
fallback.

## Generated and resolved files

Host adapters are regenerated under the ignored
`<source-root>/passport-generated/` tree. They must be visible Moon packages,
so they cannot live under `.passport/`. Firmware and Web workspaces live under
the project's ignored `.passport/` tree.

The CLI resolves Host assets from this SDK checkout when building itself, or
from the project's Moon-resolved `.mooncakes/colmugx/ai-passport/` dependency.
It does not inspect undocumented global cache layouts or fetch a moving Host
implementation.
