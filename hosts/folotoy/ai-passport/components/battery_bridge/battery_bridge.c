#include "battery_bridge.h"

#include <stdatomic.h>

#include "bsp_battery.h"
#include "esp_err.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#define BATTERY_POLL_PERIOD_MS 1000
#define BATTERY_TASK_STACK 3072

static const char *TAG = "battery_bridge";

// Atomic so the render loop's reads never tear against the poll task.
static atomic_int_fast32_t s_soc = -1;

// One task initializes the gauge once and then polls it forever. Every poll
// is authoritative for the HUD: a valid 0..100 SOC replaces the cache, and
// a failed read stores -1 immediately, so the HUD falls back to "--%" the
// moment the gauge stops standing behind its number instead of showing a
// stale value indefinitely. Failure logs fire only on the transition into
// a bad stretch, so a board without the gauge stays quiet after the one
// init error.
static void battery_task(void *arg) {
    (void)arg;
    esp_err_t err = bsp_battery_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Battery gauge unavailable (%s); HUD will show --%%",
                 esp_err_to_name(err));
        // Keep polling: cw_read fails fast while no device is attached, and
        // the application must not abort because battery is unavailable.
    }
    bool reading_valid = false;
    for (;;) {
        int soc = bsp_battery_soc();
        if (soc >= 0 && soc <= 100) {
            if (!reading_valid) {
                ESP_LOGI(TAG, "Battery gauge ready, SOC=%d mV=%d",
                         soc, bsp_battery_mv());
            }
            reading_valid = true;
            atomic_store(&s_soc, soc);
        } else {
            if (reading_valid) {
                ESP_LOGW(TAG, "CW2017 SOC read failed (%d); HUD shows --%%",
                         soc);
            }
            reading_valid = false;
            atomic_store(&s_soc, -1);
        }
        vTaskDelay(pdMS_TO_TICKS(BATTERY_POLL_PERIOD_MS));
    }
}

void ai_passport_battery_bridge_init(void) {
    // The gauge init can block for seconds waiting for the first SOC
    // computation, so it runs inside the task; the frame loop starts
    // immediately and shows "--%" until the first valid reading.
    if (xTaskCreate(battery_task, "battery", BATTERY_TASK_STACK,
                    NULL, tskIDLE_PRIORITY + 1, NULL) != pdPASS) {
        ESP_LOGE(TAG, "Battery task creation failed; HUD stays at --%%");
    }
}

int32_t ai_passport_battery_soc(void) {
    return (int32_t)atomic_load(&s_soc);
}
