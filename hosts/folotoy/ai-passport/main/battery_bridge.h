// Battery bridge: the only C seam between the CW2017 gauge and the MoonBit
// device runtime. The pinned FoloToy BSP submodule owns the chip; this
// module owns polling cadence and the cached reading the per-frame HUD
// path reads.
#pragma once

#include <stdint.h>

// Initializes the gauge and starts the one-second polling task. Never
// blocks: the possibly-slow first SOC computation happens inside the task,
// so the caller's frame loop starts immediately and the HUD shows "--%"
// until the first valid reading arrives. A missing or unreadable gauge is
// logged once and tolerated; the bridge keeps answering -1.
void ai_passport_battery_bridge_init(void);

// Last polled state of charge: 0..100, or -1 when unavailable. Safe to call
// from the render loop; it only reads the cache the poll task updates.
int32_t ai_passport_battery_soc(void);
