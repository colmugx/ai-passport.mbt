#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#include "battery_bridge.h"
#include "bsp_display.h"
#include "button_bridge.h"
#include "display_bridge.h"
#include "esp_err.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "sound_player.h"

extern void moonbit_runtime_init(int argc, char **argv);
extern void moonbit_init(void);
extern int32_t ai_passport_mbt_probe(void);
extern int32_t ai_passport_mbt_app_init(void);
extern int32_t ai_passport_mbt_app_update(void);
extern int32_t ai_passport_mbt_app_draw(void);
extern int32_t ai_passport_mbt_app_present(void);
// Device-only App facts (the project's device entry): raw press delivery and
// the absolute startup audio output state. app_main owns no button semantics.
// Verified against the captured C (generated/moonbit): every MoonBit export —
// including the Unit-returning ones — has C type int32_t(...).
extern int32_t ai_passport_mbt_input_press(int32_t code);
extern int32_t ai_passport_mbt_audio_volume(void);
extern int32_t ai_passport_mbt_audio_muted(void);

#define FRAME_PERIOD_US 33333LL
#define STATS_PERIOD_US 5000000LL
#define INTERNAL_HEAP_CAPS (MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT)

static const char *TAG = "ai_passport";

static void log_heap(const char *phase) {
    ESP_LOGI(TAG,
             "heap phase=%s free_internal=%u min_free_internal=%u largest_internal=%u",
             phase,
             (unsigned)heap_caps_get_free_size(INTERNAL_HEAP_CAPS),
             (unsigned)heap_caps_get_minimum_free_size(INTERNAL_HEAP_CAPS),
             (unsigned)heap_caps_get_largest_free_block(INTERNAL_HEAP_CAPS));
}

void app_main(void) {
    moonbit_runtime_init(0, NULL);
    moonbit_init();
    const int32_t probe = ai_passport_mbt_probe();
    ESP_LOGI(TAG, "MoonBit bridge probe: 0x%04" PRIx32, (uint32_t)probe);
    if (probe != 0xA17E) {
        ESP_LOGE(TAG, "MoonBit bridge probe mismatch");
        abort();
    }

    ESP_ERROR_CHECK(ai_passport_display_init());
    bsp_display_backlight(60);
    // Bring up the sound Host muted before application initialization so
    // play() is valid even inside passport_main. The application publishes
    // its authoritative master output immediately after initialization,
    // before the first audible chunk can leave the codec.
    log_heap("before_audio_init");
    const esp_err_t sound_err = ai_passport_sound_player_start(0, true);
    if (sound_err != ESP_OK) {
        ESP_LOGE(TAG, "Sound runtime unavailable (%s); running silent",
                 esp_err_to_name(sound_err));
    }
    log_heap(sound_err == ESP_OK ? "after_audio_init" : "after_audio_init_failed");

    log_heap("before_app_init");
    (void)ai_passport_mbt_app_init();
    ai_passport_sound_set_output(
        ai_passport_mbt_audio_volume(), ai_passport_mbt_audio_muted() != 0);
    log_heap("after_app_init");

    // Battery never blocks the frame loop: the bridge task does the
    // possibly-slow first CW2017 SOC computation and then polls at 1 Hz.
    ai_passport_battery_bridge_init();

    // Physical buttons last: the bridge only enqueues raw UP/DOWN/OK press
    // codes onto its own bounded queue, so buttons may also come up when
    // sound failed (the App's semantics still run; the output setter then
    // reaches no codec). A button failure only disables the controls; the
    // application and sound keep running.
    if (ai_passport_button_bridge_init() != ESP_OK) {
        ESP_LOGW(TAG, "Continuing without button controls");
    }

    uint64_t frames = 0;
    bool first_frame_logged = false;
    uint64_t missed_deadlines = 0;
    int64_t total_update_us = 0;
    int64_t total_draw_us = 0;
    int64_t total_present_us = 0;
    int64_t total_frame_us = 0;
    int64_t window_start_us = esp_timer_get_time();
    int64_t deadline_us = window_start_us;

    for (;;) {
        const int64_t frame_start_us = esp_timer_get_time();
        // Frame order: at most ONE queued physical press per frame enters
        // the App (a press pulse latches exactly one just_pressed edge, and
        // draining several identical presses before one advance() would
        // coalesce them into one action), then the App update applies the
        // edge and mirrors the absolute output state to the transport.
        ai_passport_button_t press;
        if (ai_passport_button_bridge_poll(&press)) {
            (void)ai_passport_mbt_input_press((int32_t)press);
        }
        (void)ai_passport_mbt_app_update();
        const int64_t draw_start_us = esp_timer_get_time();
        (void)ai_passport_mbt_app_draw();
        const int64_t present_start_us = esp_timer_get_time();
        (void)ai_passport_mbt_app_present();
        const int64_t frame_end_us = esp_timer_get_time();

        ++frames;
        total_update_us += draw_start_us - frame_start_us;
        total_draw_us += present_start_us - draw_start_us;
        total_present_us += ai_passport_display_last_present_us();
        total_frame_us += frame_end_us - frame_start_us;
        if (!first_frame_logged) {
            log_heap("after_first_frame");
            first_frame_logged = true;
        }

        const int64_t elapsed_us = frame_end_us - window_start_us;
        if (elapsed_us >= STATS_PERIOD_US) {
            ESP_LOGI(TAG,
                     "frames=%" PRIu64 " missed_deadlines=%" PRIu64
                     " dropped_button_events=%" PRIu32
                     " avg_update_us=%" PRId64 " avg_draw_us=%" PRId64
                     " avg_present_us=%" PRId64 " avg_frame_us=%" PRId64
                     " achieved_fps_x100=%" PRId64,
                     frames, missed_deadlines,
                     ai_passport_button_dropped_events(),
                     total_update_us / (int64_t)frames,
                     total_draw_us / (int64_t)frames,
                     total_present_us / (int64_t)frames,
                     total_frame_us / (int64_t)frames,
                     (int64_t)frames * 100000000LL / elapsed_us);
            log_heap("sustained_run");
            frames = 0;
            missed_deadlines = 0;
            total_update_us = 0;
            total_draw_us = 0;
            total_present_us = 0;
            total_frame_us = 0;
            window_start_us = frame_end_us;
        }

        deadline_us += FRAME_PERIOD_US;
        const int64_t now_us = esp_timer_get_time();
        if (deadline_us <= now_us) {
            ++missed_deadlines;
            // One simulation step per presented frame. The frame work already
            // exceeded its deadline: skip the missed frame instead of
            // rendering a catch-up frame, discard the accumulated lag, and
            // start the next frame from now after one bounded scheduler yield.
            deadline_us = now_us;
            vTaskDelay(1);
            continue;
        }
        const int64_t wait_us = deadline_us - esp_timer_get_time();
        const TickType_t ticks = pdMS_TO_TICKS((wait_us + 999) / 1000);
        vTaskDelay(ticks > 0 ? ticks : 1);
    }
}
