#include "music_stream.h"

#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "bsp_audio.h"
#include "esp_err.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

// The canonical asset is embedded as raw PCM16 little-endian mono 16 kHz.
extern const uint8_t passport_music_pcm_start[] asm("_binary_passport_music_pcm_start");
extern const uint8_t passport_music_pcm_end[] asm("_binary_passport_music_pcm_end");

#define PCM_CHUNK_SAMPLES 240        // 15 ms of audio; a few hundred samples
#define PCM_CHUNK_BYTES (PCM_CHUNK_SAMPLES * (MUSIC_BITS_PER_SAMPLE / 8))
#define MUSIC_TASK_STACK 3072
#define MUSIC_TASK_PRIORITY (tskIDLE_PRIORITY + 2)
// Retry cadence for a failed write: log at most once per second, never spin.
#define MUSIC_RETRY_DELAY_MS 20
#define MUSIC_ERROR_LOG_PERIOD_MS 1000

// Packed desired output: bits 0..7 hold the remembered volume (0..100),
// bit 8 the mute flag. One atomic store publishes volume and mute as one
// coherent snapshot; there is no semantic command queue to drop from.
#define MUSIC_OUTPUT_VOLUME_MASK 0xFFu
#define MUSIC_OUTPUT_MUTED_BIT 0x100u
// "Nothing applied yet": never a valid packed state, so the music task
// writes the startup output to the codec exactly once before the first PCM
// sample and then only on real changes.
#define MUSIC_OUTPUT_UNAPPLIED 0xFFFFFFFFu

static const char *TAG = "music_stream";

static bool s_started;
// Loop-wrapped write offset in samples (bytes / 2), published for the
// application's playback-position reads. Atomic: the render loop reads it
// without a lock.
static atomic_int s_loop_sample;
// Desired absolute output state, written by the render-side mirror with one
// atomic store (latest state wins). A failed music start simply means
// nothing ever consumes the state.
static atomic_uint s_desired;
// Last packed state applied to the codec. Only the music task reads or
// writes it, so no extra synchronization is needed.
static unsigned s_applied = MUSIC_OUTPUT_UNAPPLIED;

// Codec-facing volume for a packed state: zero while muted, otherwise the
// remembered setting preserved by the App's Controls.
static int output_codec_volume(unsigned packed) {
    const bool muted = (packed & MUSIC_OUTPUT_MUTED_BIT) != 0u;
    return muted ? 0 : (int)(packed & MUSIC_OUTPUT_VOLUME_MASK);
}

// Applies the desired output when it changed. Runs in the music task
// between PCM writes, so the codec volume change and its log never execute
// in the render task; a redundant identical state writes nothing.
static void apply_desired_output(void) {
    const unsigned desired = atomic_load(&s_desired);
    if (desired == s_applied) {
        return;
    }
    bsp_audio_set_volume((uint8_t)output_codec_volume(desired));
    ESP_LOGI(TAG, "output volume=%u muted=%d",
             desired & MUSIC_OUTPUT_VOLUME_MASK,
             (desired & MUSIC_OUTPUT_MUTED_BIT) != 0u ? 1 : 0);
    s_applied = desired;
}

// Streams bounded chunks straight from flash-mapped memory into the codec.
// bsp_audio_write blocks until the DMA queue accepts the chunk, which paces
// the loop at real time. At end of stream the offset restarts at zero: the
// loop boundary does not allocate and cannot accumulate latency.
static void music_task(void *arg) {
    (void)arg;
    apply_desired_output();
    const size_t total = (size_t)(passport_music_pcm_end - passport_music_pcm_start);
    size_t offset = 0;
    TickType_t last_error_log = 0;
    for (;;) {
        apply_desired_output();
        size_t remaining = total - offset;
        size_t bytes = remaining < PCM_CHUNK_BYTES ? remaining : PCM_CHUNK_BYTES;
        esp_err_t err = bsp_audio_write(passport_music_pcm_start + offset, bytes);
        if (err == ESP_OK) {
            offset += bytes;
            if (offset >= total) {
                offset = 0; // loop the authored track from its beginning
            }
            atomic_store(&s_loop_sample, (int)(offset / 2));
            continue;
        }
        // Keep the offset: a failed write consumed no samples, so the track
        // resumes exactly where it stopped instead of skipping audio.
        TickType_t now = xTaskGetTickCount();
        if ((now - last_error_log) >= pdMS_TO_TICKS(MUSIC_ERROR_LOG_PERIOD_MS)) {
            last_error_log = now;
            ESP_LOGE(TAG, "PCM write failed (%s); retrying",
                     esp_err_to_name(err));
        }
        vTaskDelay(pdMS_TO_TICKS(MUSIC_RETRY_DELAY_MS));
    }
}

esp_err_t ai_passport_music_start(int initial_volume, bool initial_muted) {
    if (s_started) {
        return ESP_OK;
    }
    esp_err_t err = bsp_audio_init();
    if (err != ESP_OK) {
        return err;
    }
    err = bsp_audio_set_format(MUSIC_SAMPLE_RATE_HZ, MUSIC_BITS_PER_SAMPLE,
                               MUSIC_CHANNELS);
    if (err != ESP_OK) {
        return err;
    }
    // The App is authoritative before the first PCM sample: its startup
    // facts are published here and the task below applies them from the
    // audio-owning context. No second startup-volume constant lives here.
    ai_passport_music_set_output(initial_volume, initial_muted);
    if (xTaskCreate(music_task, "music_stream", MUSIC_TASK_STACK, NULL,
                    MUSIC_TASK_PRIORITY, NULL) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    s_started = true;
    const size_t total = (size_t)(passport_music_pcm_end - passport_music_pcm_start);
    ESP_LOGI(TAG,
             "Music streaming %u bytes of PCM16/%dHz/mono in %u-sample chunks",
             (unsigned)total, MUSIC_SAMPLE_RATE_HZ, PCM_CHUNK_SAMPLES);
    return ESP_OK;
}

void ai_passport_music_set_output(int volume, bool muted) {
    unsigned packed = (unsigned)volume & MUSIC_OUTPUT_VOLUME_MASK;
    if (muted) {
        packed |= MUSIC_OUTPUT_MUTED_BIT;
    }
    atomic_store(&s_desired, packed);
}

int32_t ai_passport_music_available(void) {
    return s_started ? 1 : 0;
}

int64_t ai_passport_music_position_us(void) {
    if (!s_started) {
        // Unavailable: no musical meaning. The boot clock is never
        // fabricated into a position here; availability — not the position
        // value — reports the failure, and the portable App's fallback
        // clock owns unavailability.
        return 0;
    }
    const int sample = atomic_load(&s_loop_sample);
    return (int64_t)sample * 1000000LL / MUSIC_SAMPLE_RATE_HZ;
}
