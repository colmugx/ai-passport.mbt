// Monotonic device frame clock in microseconds (esp_timer passthrough).
// Feeds the portable application's fixed-step 30 Hz accumulator; unlike the
// music position it never wraps, so it is safe as a time base.
#pragma once

#include <stdint.h>

int64_t ai_passport_now_us(void);
