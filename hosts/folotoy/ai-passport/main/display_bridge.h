#pragma once

#include <stdint.h>
#include "esp_err.h"

esp_err_t ai_passport_display_init(void);
int64_t ai_passport_display_last_present_us(void);
int32_t ai_passport_display_backlight_level(void);
void ai_passport_display_set_backlight(int32_t level);
