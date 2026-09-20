# FoloToy AI Passport ESP32-C3 host

ESP-IDF 5.5.3 firmware for the FoloToy AI Passport ESP32-C3, owned by the SDK as the `folotoy-ai-passport` Host. It supplies capabilities and transport only; the portable MoonBit application owns all semantics, and web and physical Hosts execute the same compiled application.

## Hardware facts

- ESP32-C3, 8 MB flash, no PSRAM, USB-Serial-JTAG console. Wi-Fi and BLE stay uninitialized.
- Display: ST7789P3 240x320 SPI panel. The v0.1 logical display contract is 120x160 RGB565; `display_bridge` doubles each logical pixel (SCALE 2) into double-buffered DMA strips of 240x40 physical rows (19,200 bytes each), two buffers outstanding, eight strips per frame, with per-strip completion semaphores and byte-swapped RGB565 at this one device boundary. There is no full physical framebuffer. The 40 MHz SPI transfer lower bound for a 153,600-byte physical frame is about 30.7 ms (~32.5 FPS) before overhead.
- Buttons: UP / DOWN / OK on one shared GPIO0/ADC1_CH0 line. `button_bridge` delivers raw device-neutral press codes only (0 = Up, 1 = Down, 2 = Ok) through a bounded eight-slot queue drained at most once per frame; dropped events are counted in telemetry.
- Battery: CW2017 gauge on the shared I2C0 bus (address 0x63), polled at 1000 ms into an atomic cache answering 0..100 or -1.
- Audio: ES8311 codec (address 0x18) on the same I2C bus. `sound_player` embeds the shared APSB bank in flash without copying PCM payloads to heap. Four independent playback slots feed one task that sums 240-sample chunks, clamps to PCM16, and uniquely owns codec writes. Pause/resume/stop and positions are per playback; master volume/mute is published atomically. An empty bank is valid and keeps every `play` request explicitly unavailable. The format is fixed: signed PCM16 little-endian, mono, 16000 Hz.
- Frame schedule: one FreeRTOS frame task with a 33333 us period, one application update per presented frame, no catch-up renders; heap and frame statistics logged every five seconds.

## Device ABI

`main/app_main.c` calls only generic MoonBit exports and nothing application-specific: `ai_passport_mbt_probe` (must answer 0xA17E), `ai_passport_mbt_app_init`, `ai_passport_mbt_app_update`, `ai_passport_mbt_app_draw`, `ai_passport_mbt_app_present`, `ai_passport_mbt_input_press`, `ai_passport_mbt_audio_volume`, `ai_passport_mbt_audio_muted`. The transport is started from the App's own startup output facts; the clock (`ai_passport_now_us` in `components/clock_bridge`) is an esp_timer passthrough feeding the application's fixed-step accumulator.

## Build pipeline

`passport build --host folotoy-ai-passport` materializes a build workspace at `<project>/.passport/folotoy-ai-passport/`. Before copying the current Host, the CLI validates all declared sounds and compiles the shared APSB v1 bytes. It then removes stale Host/source/generated entries while preserving only the incremental ESP-IDF state (`build/`, `managed_components/`, `sdkconfig`, `sdkconfig.old`), so files removed or renamed by a newer SDK cannot survive into firmware, and writes `sounds.bank` at the workspace root. `sound_player` embeds and strictly validates those exact bytes. The build then captures the project device entry's MoonBit C into `components/moonbit_device/generated/moonbit/`, connects the external FoloToy checkout (below), and runs `idf.py reconfigure` plus `idf.py build`. `flash.sh` and `monitor.sh` are thin `idf.py` wrappers (pass `-p PORT` through) meant to run there.

Capture mechanism: the CLI temporarily points the device entry package's `options.link.native.cc` at `tools/moon_cc_capture.py` with `MOON_CC_CAPTURE_DIR` set (and `MOONBIT_NEW_NATIVE=0`), restoring `moon.pkg` byte-identically afterwards. The wrapper records the compiler arguments and copies the generated C under the capture directory; `sources.txt` is the manifest `components/moonbit_device/CMakeLists.txt` compiles from. An empty `-o` placeholder exists only for Moon's internal build graph; ESP-IDF never reads it. Without `MOON_CC_CAPTURE_DIR` the wrapper execs the real host compiler, so ordinary native builds are unaffected.

Toolchain requirements:

- ESP-IDF pinned to [v5.5.3](https://github.com/espressif/esp-idf/tree/v5.5.3); source its `export.sh` before building.
- `moon 0.1.20260915 (2e1a46d 2026-09-15)`. `moonbit-runtime.sha256` pins the distribution's runtime sources and headers under `MOON_HOME` (default `~/.moon`); `components/moonbit_runtime` compiles them directly. Do not substitute runtime sources without updating the compiler and hash manifest together.

## Partition budget

`partitions.csv` sizes the factory app at 0x380000 at offset 0x10000 so a flash-resident sound bank (a 76 s total PCM payload is ~2.4 MB) fits next to the ~650 KB program image inside the 8 MB flash, leaving ~4.4 MB unused; sizes stay 64 KB aligned. `sdkconfig.defaults` selects the custom table and pins `CONFIG_FREERTOS_HZ=1000`. The build contract keeps audio payloads within the firmware budget; the ESP-IDF link step remains the final capacity check.

## External FoloToy dependency

This SDK — source tree and published Mooncakes archive alike — contains only ai-passport-owned Host glue; the FoloToy BSP is an external dependency and its source never enters this repository. The build resolves a checkout of [FoloToy/ai-passport](https://github.com/FoloToy/ai-passport) at the single tested revision [c21a015d44f2bcc02b4d859532d74cd7aefe69be](https://github.com/FoloToy/ai-passport/commit/c21a015d44f2bcc02b4d859532d74cd7aefe69be) (MIT), in order:

1. the project contract's `hostDependencies["folotoy-ai-passport"].path` (the reference template's pinned `external/folotoy-ai-passport` submodule) — authoritative when declared; a missing or drifted checkout is a project error, never silently replaced;
2. the CLI-managed clone at `<project>/.passport/deps/folotoy-ai-passport/<revision>/`, cloned or re-pinned only when missing or on the wrong revision — never a moving ref.

Every build verifies the resolved checkout against `components/folotoy_bsp/bsp.sha256` (the content manifest is the authority, not the ref), logs the dependency path, revision, and origin (project-provided vs CLI-managed), and connects it by writing a one-line `upstream.cmake` into the workspace: the folotoy_bsp component compiles the upstream sources in place, nothing is copied.

The component's `CMakeLists.txt` compiles only `bsp_display.c`, `bsp_i2c.c`, `bsp_battery.c`, `bsp_audio.c` and `bsp_button.c`, deliberately excluding the upstream LVGL display source so no UI framework enters the firmware; `idf_component.yml` pins `espressif/esp_codec_dev` 1.6.2, `espressif/button` 4.2.0 and the upstream IDF range `>=5.5.3,<5.6.0` (`dependencies.lock` records the resolved managed components). `bsp_i2c.c` remains the single owner of the shared I2C0 bus.
