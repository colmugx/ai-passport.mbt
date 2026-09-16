# AGENTS.md

## Repository scope

This repository is the `colmugx/ai-passport` Mooncakes application SDK **and its co-versioned Host toolchain**. It owns reusable MoonBit application APIs, runtime logic, the `passport` CLI, Host descriptors, Host runtime assets, tests, and the implementation needed to build/deploy applications to Hosts that this project explicitly supports.

Do not add a permanent Forest Walk starter or other application semantics here. Example/starter applications belong in downstream application repositories. Host-specific implementation may contain ESP-IDF, BSP, browser, flashing, provisioning, pin, bus, controller, or toolchain details when they are required to implement that Host; those details must stay behind the Host boundary and must not leak into public application APIs.

This repository and its published Mooncakes archive carry **no third-party product or hardware source code**. A Host directory contains only ai-passport-owned glue/adapters, build recipes, and deterministic metadata (hash manifests, pinned revisions) describing external dependencies. Third-party code (e.g. the FoloToy BSP) is resolved at build time from a project-provided checkout or a CLI-managed pinned clone under the project's `.passport/` tree — never vendored, copied, or committed here.

## Architectural rules

1. **Host is the only backend abstraction.** Do not introduce parallel Product/Board/DeviceTarget vocabularies for backend selection.
2. A Host is one explicitly supported and validated execution environment. Do not turn the public contract into arbitrary GPIO or board configuration.
3. Application code depends on semantic SDK capabilities; it must not import Host implementation details such as ESP-IDF, GPIO, ADC, SPI, I2S, I2C, display controllers, codecs, browser DOM, or WebAudio APIs.
4. Web and physical Hosts execute the same compiled MoonBit application semantics. Host code supplies capabilities and transport; it does not reimplement application behavior.
5. The v0.1 logical display contract is 120×160 RGB565. Host presentation details remain behind display contracts.
6. Buttons are semantic `Up`, `Down`, and `Ok` values.
7. Graphics public APIs do not expose framebuffer, strip-rendering, or device-controller details.
8. Music supports at most four monophonic voices.
9. Prefer reusable pure MoonBit logic. Keep Host glue narrow, measurable, and replaceable within the Host implementation.
10. SDK library, CLI, and Host assets are one release unit. Do not fetch an unpinned "latest" Host implementation at build time.
11. Do not add QEMU or a hardware emulator unless the project explicitly chooses that direction in a later round.
12. Generated application artifacts belong under ignored build/workspace directories; do not make generated project output part of the public authoring surface.

Forest Walk is a downstream reference application, not SDK/tooling semantics. CLI/Host tooling must remain application-generic.

## MoonBit layout and tooling

`moon.mod` declares the module; each package directory has a `moon.pkg`. Source files in one package share a namespace. Keep related declarations together and separate MoonBit blocks with `///|`. Put deprecated declarations in `deprecated.mbt` when they must remain. `*_test.mbt` files are black-box tests; `*_wbtest.mbt` files are white-box tests.

Use `moon ide` (`peek-def`, `outline`, `find-references`) for code navigation. `moon info` regenerates `pkg.generated.mbti` public interfaces; do not edit those files directly. Review interface diffs after public API work. Use `moon fmt` for formatting and `moon test` for tests; update snapshots only for intended behavior changes. Prefer assertions for stable results and `debug_inspect` with `Debug` for structured diagnostic snapshots. `moon coverage analyze` can identify untested code.

Let normal Moon project operations (`moon check` / `moon build`) resolve and materialize declared dependencies. Do not couple runtime tooling to deprecated installer behavior or undocumented global cache directory layouts.

## Quality gates

- `moon check --output-json` and `moon test --output-json` succeed for every target the affected package supports.
- The Web Host/CLI real-browser integration gate stays mandatory when those paths are touched.
- Host-specific build gates are required once that Host backend is implemented; never substitute host tests for physical-device evidence.
- `moon info` produces only intended public interface changes.
- `moon fmt` leaves the tree clean.
- `git diff --exit-code` is clean after generators/formatters.
- Boundary conditions, failure paths, and filesystem/project-contract inputs are tested.
- Public API/ABI changes are explicit; do not silently revise Wasm ABI v0 during unrelated refactors.
