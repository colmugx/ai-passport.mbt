#include "microphone_bridge.h"

#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>

#include "bsp_audio.h"
#include "esp_err.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#define MIC_SAMPLE_RATE_HZ 16000
#define MIC_CHUNK_SAMPLES 240
#define MIC_RING_SAMPLES 4096
#define MIC_TASK_STACK 3072

enum { MIC_IDLE = 1, MIC_RECORDING = 3, MIC_FAILED = 5 };

static const char *TAG = "microphone_bridge";
static SemaphoreHandle_t s_lock;
static TaskHandle_t s_task;
static int16_t s_ring[MIC_RING_SAMPLES];
static uint32_t s_head;
static uint32_t s_count;
static atomic_int s_status = ATOMIC_VAR_INIT(MIC_IDLE);
static atomic_uint s_dropped;
static atomic_uint s_generation;

static void capture_task(void *arg) {
    (void)arg;
    int16_t chunk[MIC_CHUNK_SAMPLES];
    for (;;) {
        if (atomic_load(&s_status) != MIC_RECORDING) {
            vTaskDelay(pdMS_TO_TICKS(10));
            continue;
        }
        const unsigned generation = atomic_load(&s_generation);
        // The BSP owns I2S RX and returns only after a complete chunk. The
        // output task independently owns I2S TX; neither task changes format.
        const esp_err_t err = bsp_audio_read(chunk, sizeof(chunk));
        if (err != ESP_OK) {
            if (generation == atomic_load(&s_generation) &&
                atomic_load(&s_status) == MIC_RECORDING) {
                ESP_LOGE(TAG, "microphone PCM read failed (%s)", esp_err_to_name(err));
                atomic_store(&s_status, MIC_FAILED);
            }
            continue;
        }
        xSemaphoreTake(s_lock, portMAX_DELAY);
        if (generation == atomic_load(&s_generation) &&
            atomic_load(&s_status) == MIC_RECORDING) {
            for (uint32_t i = 0; i < MIC_CHUNK_SAMPLES; ++i) {
                if (s_count == MIC_RING_SAMPLES) {
                    atomic_fetch_add(&s_dropped, 1);
                    continue;
                }
                s_ring[(s_head + s_count) % MIC_RING_SAMPLES] = chunk[i];
                ++s_count;
            }
        }
        xSemaphoreGive(s_lock);
    }
}

int32_t ai_passport_mic_start(void) {
    if (atomic_load(&s_status) == MIC_RECORDING) return MIC_RECORDING;
    if (s_lock == NULL) {
        s_lock = xSemaphoreCreateMutex();
        if (s_lock == NULL) {
            ESP_LOGE(TAG, "microphone mutex allocation failed");
            atomic_store(&s_status, MIC_FAILED);
            return MIC_FAILED;
        }
    }
    // The output runtime configures this same fixed format at boot. Repeating
    // the identical format is safe; the BSP does not reopen the codec.
    esp_err_t err = bsp_audio_init();
    if (err == ESP_OK) {
        err = bsp_audio_set_format(MIC_SAMPLE_RATE_HZ, 16, 1);
    }
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "microphone init failed (%s)", esp_err_to_name(err));
        atomic_store(&s_status, MIC_FAILED);
        return MIC_FAILED;
    }
    if (s_task == NULL && xTaskCreate(capture_task, "microphone",
                                      MIC_TASK_STACK, NULL, tskIDLE_PRIORITY + 1,
                                      &s_task) != pdPASS) {
        ESP_LOGE(TAG, "microphone task allocation failed");
        atomic_store(&s_status, MIC_FAILED);
        return MIC_FAILED;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_head = 0;
    s_count = 0;
    atomic_fetch_add(&s_generation, 1);
    atomic_store(&s_dropped, 0);
    atomic_store(&s_status, MIC_RECORDING);
    xSemaphoreGive(s_lock);
    ESP_LOGI(TAG, "microphone recording started: PCM16 mono 16000 Hz");
    return MIC_RECORDING;
}

int32_t ai_passport_mic_status(void) {
    return atomic_load(&s_status);
}

void ai_passport_mic_stop(void) {
    if (s_lock == NULL) return;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    atomic_store(&s_status, MIC_IDLE);
    atomic_fetch_add(&s_generation, 1);
    s_head = 0;
    s_count = 0;
    xSemaphoreGive(s_lock);
    ESP_LOGI(TAG, "microphone recording stopped");
}

int32_t ai_passport_mic_read(int32_t *out, int32_t capacity) {
    if (out == NULL || capacity <= 0 || s_lock == NULL ||
        atomic_load(&s_status) != MIC_RECORDING) {
        ESP_LOGE(TAG, "microphone read called outside recording or with bad buffer");
        return -1;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    const uint32_t count = s_count < (uint32_t)capacity ? s_count : (uint32_t)capacity;
    for (uint32_t i = 0; i < count; ++i) {
        out[i] = s_ring[s_head];
        s_head = (s_head + 1) % MIC_RING_SAMPLES;
    }
    s_count -= count;
    xSemaphoreGive(s_lock);
    return (int32_t)count;
}

int32_t ai_passport_mic_dropped_samples(void) {
    return (int32_t)atomic_load(&s_dropped);
}
