#include "clock_bridge.h"

#include "esp_timer.h"

int64_t ai_passport_now_us(void) {
    return esp_timer_get_time();
}
