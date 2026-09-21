# LVGL assessment

The SDK now owns a complete application-facing drawing path: `Canvas` offers
primitives, sprites, and text; `FrameView` exposes a read-only RGB565 row
stream; Web presents a full-resolution Wasm framebuffer; and FoloToy sends
full-resolution rows to the ST7789P3 through bounded DMA strips. Applications
can query panel dimensions, monochrome presentation capability, and optional
backlight without importing controller code.

For the current SDK, **do not add LVGL**. FoloToy's BSP makes LVGL optional,
and the Host build already excludes its source. Adding it would create a
second layout, event, memory, and render lifecycle beside the shared MoonBit
application path. On the ESP32-C3 without PSRAM, the existing full-resolution
Canvas and DMA strips already need physical memory and frame-rate measurement;
another GUI framework would add pressure before a use case justifies it.

If a later application needs complex widgets, localization, or accessibility
features beyond the MoonBit drawing API, measure that requirement and compare
an SDK-native implementation with a Host-local LVGL renderer. Keep the public
application contract independent of LVGL either way.
