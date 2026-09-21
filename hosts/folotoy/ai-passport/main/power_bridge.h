#pragma once

#include <stdint.h>

// Internal native Host ABI. -1 means button-only wake; positive milliseconds
// also enable an application-visible timer wake. Returns 1 if accepted.
int32_t ai_passport_power_request(int32_t wake_after_ms);
int32_t ai_passport_power_wake_reason(void);

// Called by the owning frame task after presentation, never from MoonBit.
int ai_passport_power_poll_and_sleep(void);
