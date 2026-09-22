#include "power_bridge.h"

#include <stdbool.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>

#include "bsp_audio.h"
#include "bsp_button.h"
#include "bsp_pins.h"
#include "display_bridge.h"
#include "microphone_bridge.h"
#include "sound_player.h"
#include "esp_err.h"
#include "esp_log.h"
#include "esp_sleep.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#define POWER_BUTTON_POLL_MS 30
#define POWER_RELEASE_TIMEOUT_MS 5000
#define POWER_MAX_TIMED_SLEEP_MS 86400000

static const char *TAG = "power_bridge";
static const uint16_t s_button_windows[BSP_BTN_COUNT][2] = BSP_BTN_MV_TABLE;
static atomic_bool s_requested;
static atomic_int s_duration_ms;
static atomic_int s_wake_reason; // 0 none, 1 button, 2 timer, 3 other

static bool button_active(void) {
    const int mv = bsp_button_read_mv();
    if (mv < 0) {
        ESP_LOGE(TAG, "button ADC read failed during sleep transition");
        abort();
    }
    for (int i = 0; i < BSP_BTN_COUNT; ++i) {
        if (mv >= s_button_windows[i][0] && mv < s_button_windows[i][1]) {
            return true;
        }
    }
    return false;
}

int32_t ai_passport_power_request(int32_t wake_after_ms) {
    if (wake_after_ms != -1 &&
        (wake_after_ms <= 0 || wake_after_ms > POWER_MAX_TIMED_SLEEP_MS)) {
        ESP_LOGE(TAG, "invalid sleep duration=%ld ms", (long)wake_after_ms);
        abort();
    }
    bool expected = false;
    if (!atomic_compare_exchange_strong(&s_requested, &expected, true)) return 0;
    atomic_store(&s_duration_ms, wake_after_ms);
    atomic_store(&s_wake_reason, 0);
    ESP_LOGI(TAG, "application requested sleep duration_ms=%ld", (long)wake_after_ms);
    return 1;
}

int32_t ai_passport_power_wake_reason(void) {
    return atomic_load(&s_wake_reason);
}

int ai_passport_power_poll_and_sleep(void) {
    if (!atomic_exchange(&s_requested, false)) return 0;
    const int32_t duration_ms = atomic_load(&s_duration_ms);
    const int64_t release_deadline = esp_timer_get_time() +
                                     POWER_RELEASE_TIMEOUT_MS * 1000LL;
    while (button_active()) {
        if (esp_timer_get_time() >= release_deadline) {
            ESP_LOGE(TAG, "button remained held for %d ms before sleep",
                     POWER_RELEASE_TIMEOUT_MS);
            abort();
        }
        vTaskDelay(pdMS_TO_TICKS(POWER_BUTTON_POLL_MS));
    }

    // Both I2S directions must be idle before the BSP suspends the codec.
    // capture_stop itself must never block the application frame task; only
    // this power transition waits, and even here the wait is bounded.
    ai_passport_mic_stop();
    if (!ai_passport_mic_wait_idle(250)) {
        ESP_LOGE(TAG, "microphone RX remained active; sleep request canceled");
        return 0;
    }
    ai_passport_sound_player_suspend();
    const int32_t light_level = ai_passport_display_backlight_level();
    ai_passport_display_set_backlight(0);
    ESP_ERROR_CHECK(bsp_audio_sleep());
    const int64_t started_us = esp_timer_get_time();
    const int64_t deadline_us = duration_ms < 0 ? INT64_MAX :
                                started_us + (int64_t)duration_ms * 1000;
    ESP_LOGI(TAG, "entering light sleep; button ADC sampled every %d ms",
             POWER_BUTTON_POLL_MS);

    int reason = 3;
    int stable_button_samples = 0;
    for (;;) {
        int64_t interval_us = POWER_BUTTON_POLL_MS * 1000LL;
        if (duration_ms >= 0) {
            const int64_t remaining = deadline_us - esp_timer_get_time();
            if (remaining <= 0) { reason = 2; break; }
            if (remaining < interval_us) interval_us = remaining;
        }
        ESP_ERROR_CHECK(esp_sleep_enable_timer_wakeup((uint64_t)interval_us));
        ESP_ERROR_CHECK(esp_light_sleep_start());
        const esp_sleep_wakeup_cause_t raw_cause = esp_sleep_get_wakeup_cause();
        if (raw_cause != ESP_SLEEP_WAKEUP_TIMER) {
            ESP_LOGW(TAG, "unexpected light-sleep wake cause=%d", raw_cause);
            reason = 3;
            break;
        }
        if (button_active()) {
            ++stable_button_samples;
            if (stable_button_samples >= 2) { reason = 1; break; }
        } else {
            stable_button_samples = 0;
        }
    }

    ESP_ERROR_CHECK(esp_sleep_disable_wakeup_source(ESP_SLEEP_WAKEUP_TIMER));
    ESP_ERROR_CHECK(bsp_audio_wake());
    ai_passport_sound_player_resume();
    ai_passport_display_set_backlight(light_level);
    atomic_store(&s_wake_reason, reason);
    ESP_LOGI(TAG, "light sleep complete cause=%d elapsed_ms=%lld", reason,
             (long long)((esp_timer_get_time() - started_us) / 1000));
    return 1;
}
