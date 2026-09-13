# AGENTS.md

## Repository scope

This repository is only the reusable Mooncakes SDK for AI Passport. It contains MoonBit packages, pure runtime logic, public API contracts, graphics, input, music, audio and battery abstractions, tests, and replaceable platform driver interfaces.

Do not add a permanent Forest Walk starter or demo application, a GitHub Template, Web Canvas or WebAudio preview, raylib preview, ESP-IDF firmware project, FoloToy BSP copy, flashing or monitor tooling, provisioning, project scaffolding, or device GPIO numbers in public APIs. Forest Walk was removed from this SDK; it must be recovered from git history and migrated into the separate `ai-passport-template` repository. Do not recreate it here or claim that migration is already complete.

## Architectural rules

1. This repository contains the reusable Mooncakes SDK only.
2. Do not implement the GitHub Template in this repository.
3. Host and device backends implement the same SDK semantics.
4. The v0.1 logical display is 120×160 pixels.
5. Buttons are semantic `Up`, `Down`, and `Ok` values.
6. Graphics public APIs do not expose framebuffer, strip-rendering, or device-controller details.
7. Music supports at most four monophonic voices.
8. Prefer reusable pure MoonBit logic.
9. Keep backend glue thin and replaceable.
10. Do not add QEMU or a hardware emulator to this repository.

Public app code must not import ESP-IDF, raylib, GPIO, ADC, SPI, I2S, I2C, ST7789, ES8311, or CW2017 APIs. Scope changes require updating `docs/PLAN.md`.

## MoonBit layout and tooling

`moon.mod` declares the module; each package directory has a `moon.pkg`. Source files in one package share a namespace. Keep related declarations together and separate MoonBit blocks with `///|`. Put deprecated declarations in `deprecated.mbt` when they must remain. `*_test.mbt` files are black-box tests; `*_wbtest.mbt` files are white-box tests.

Use `moon ide` (`peek-def`, `outline`, `find-references`) for code navigation. `moon info` regenerates `pkg.generated.mbti` public interfaces; do not edit those files directly. Review interface diffs after public API work. Use `moon fmt` for formatting and `moon test` for tests; update snapshots only for intended behavior changes. Prefer assertions for stable results and `debug_inspect` with `Debug` for structured diagnostic snapshots. `moon coverage analyze` can identify untested code.

## Quality gates

- `moon check --output-json` succeeds on native and JS.
- `moon test --output-json` succeeds on native and JS.
- `moon info` produces only intended public interface changes.
- `moon fmt` leaves the tree clean.
- Boundary conditions are tested and public API changes are documented.
