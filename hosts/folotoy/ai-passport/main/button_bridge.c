#include "button_bridge.h"

#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>

#include "bsp_button.h"
#include "esp_err.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"

static const char *TAG = "button_bridge";

// The raw button-event queue, created by ai_passport_button_bridge_init.
// Input delivery owns it: nothing semantic (no volume, no mute) travels
// through it, only device-neutral button codes.
static QueueHandle_t s_events;
// Events dropped on a full queue; read by the telemetry loop. Owned here,
// not by the music transport.
static atomic_uint s_dropped_events;

// Runs in the button component's shared esp_timer task: only a bounded,
// non-blocking enqueue is allowed here — no MoonBit calls, no codec calls,
// no bsp_audio_set_volume, no blocking, no allocation, no logging. Only
// Every recognized BSP event is forwarded with its semantic button code.
static void on_button_event(bsp_btn_t button, bsp_btn_ev_t event, void *user) {
    (void)user;
    ai_passport_button_event_t item;
    switch (button) {
    case BSP_BTN_UP:
        item.button = AI_PASSPORT_BTN_UP;
        break;
    case BSP_BTN_DOWN:
        item.button = AI_PASSPORT_BTN_DOWN;
        break;
    case BSP_BTN_OK:
        item.button = AI_PASSPORT_BTN_OK;
        break;
    default:
        atomic_fetch_add(&s_dropped_events, 1);
        return;
    }
    switch (event) {
    case BSP_BTN_PRESS:
        item.kind = AI_PASSPORT_EVENT_PRESS;
        break;
    case BSP_BTN_CLICK:
        item.kind = AI_PASSPORT_EVENT_CLICK;
        break;
    case BSP_BTN_DOUBLE:
        item.kind = AI_PASSPORT_EVENT_DOUBLE_CLICK;
        break;
    case BSP_BTN_LONG:
        item.kind = AI_PASSPORT_EVENT_LONG_PRESS;
        break;
    default:
        atomic_fetch_add(&s_dropped_events, 1);
        return;
    }
    if (s_events == NULL || xQueueSend(s_events, &item, 0) != pdTRUE) {
        atomic_fetch_add(&s_dropped_events, 1);
    }
}

esp_err_t ai_passport_button_bridge_init(void) {
    if (s_events == NULL) {
        s_events = xQueueCreate(BUTTON_EVENT_QUEUE_LENGTH,
                                sizeof(ai_passport_button_event_t));
        if (s_events == NULL) {
            return ESP_ERR_NO_MEM;
        }
    }
    esp_err_t err = bsp_button_init(on_button_event, NULL);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Buttons unavailable (%s); controls disabled",
                 esp_err_to_name(err));
        return err;
    }
    ESP_LOGI(TAG, "Buttons ready: UP/DOWN/OK press, click, double, long events");
    return ESP_OK;
}

bool ai_passport_button_bridge_poll(ai_passport_button_event_t *out) {
    if (s_events == NULL) {
        return false;
    }
    return xQueueReceive(s_events, out, 0) == pdTRUE;
}

uint32_t ai_passport_button_dropped_events(void) {
    return (uint32_t)atomic_load(&s_dropped_events);
}
