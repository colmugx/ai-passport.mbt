#include "sound_player.h"

#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>

#include "bsp_audio.h"
#include "esp_err.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

extern const uint8_t sounds_bank_start[] __asm__("_binary_sounds_bank_start");
extern const uint8_t sounds_bank_end[] __asm__("_binary_sounds_bank_end");

#define APSB_HEADER_BYTES 16u
#define APSB_ENTRY_BYTES 8u
#define SOUND_PLAYBACK_SLOTS 4
#define SOUND_CHUNK_SAMPLES 240
#define SOUND_TASK_STACK 4096
#define SOUND_TASK_PRIORITY (tskIDLE_PRIORITY + 2)
#define SOUND_IDLE_DELAY_MS 10
#define SOUND_RETRY_DELAY_MS 20
#define SOUND_ERROR_LOG_PERIOD_MS 1000

#define OUTPUT_VOLUME_MASK 0xFFu
#define OUTPUT_MUTED_BIT 0x100u
#define OUTPUT_UNAPPLIED 0xFFFFFFFFu

typedef enum {
    SLOT_FREE = 0,
    SLOT_PLAYING,
    SLOT_PAUSED,
} slot_state_t;

typedef struct {
    int32_t handle;
    uint32_t sound_id;
    uint32_t cursor;
    bool looping;
    slot_state_t state;
} playback_slot_t;

typedef struct {
    int slot_index;
    int32_t handle;
    uint32_t cursor;
    uint32_t next_cursor;
    bool ended;
} mixed_playback_t;

static const char *TAG = "sound_player";
static SemaphoreHandle_t s_lock;
static SemaphoreHandle_t s_io_lock;
static bool s_suspended;
static playback_slot_t s_slots[SOUND_PLAYBACK_SLOTS];
static uint32_t s_sound_count;
static uint32_t s_next_handle = 1;
static atomic_bool s_prepared;
static atomic_bool s_enabled;
static atomic_bool s_started;
static atomic_uint s_desired_output;
static unsigned s_applied_output = OUTPUT_UNAPPLIED;

static uint16_t read_u16_le(const uint8_t *bytes) {
    return (uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8);
}

static uint32_t read_u32_le(const uint8_t *bytes) {
    return (uint32_t)bytes[0] |
           ((uint32_t)bytes[1] << 8) |
           ((uint32_t)bytes[2] << 16) |
           ((uint32_t)bytes[3] << 24);
}

static int16_t read_i16_le(const uint8_t *bytes) {
    return (int16_t)read_u16_le(bytes);
}

static const uint8_t *bank_bytes(void) {
    return sounds_bank_start;
}

static size_t bank_size(void) {
    return (size_t)(sounds_bank_end - sounds_bank_start);
}

static esp_err_t validate_bank(void) {
    const uint8_t *bank = bank_bytes();
    const size_t size = bank_size();
    if (size < APSB_HEADER_BYTES || memcmp(bank, "APSB", 4) != 0) {
        ESP_LOGE(TAG, "invalid sounds.bank: missing APSB header");
        return ESP_ERR_INVALID_SIZE;
    }
    if (read_u16_le(bank + 4) != 1u ||
        read_u16_le(bank + 6) != APSB_HEADER_BYTES ||
        read_u16_le(bank + 12) != APSB_ENTRY_BYTES ||
        read_u16_le(bank + 14) != 0u) {
        ESP_LOGE(TAG, "invalid sounds.bank: unsupported format header");
        return ESP_ERR_NOT_SUPPORTED;
    }
    const uint32_t count = read_u32_le(bank + 8);
    const uint64_t table_end = APSB_HEADER_BYTES + (uint64_t)count * APSB_ENTRY_BYTES;
    if (table_end > size) {
        ESP_LOGE(TAG, "invalid sounds.bank: truncated entry table");
        return ESP_ERR_INVALID_SIZE;
    }
    uint64_t expected_offset = table_end;
    for (uint32_t id = 0; id < count; ++id) {
        const uint8_t *entry = bank + APSB_HEADER_BYTES + id * APSB_ENTRY_BYTES;
        const uint32_t offset = read_u32_le(entry);
        const uint32_t samples = read_u32_le(entry + 4);
        if (samples == 0u || offset != expected_offset) {
            ESP_LOGE(TAG, "invalid sounds.bank entry id=%" PRIu32 " offset=%" PRIu32
                          " samples=%" PRIu32,
                     id, offset, samples);
            return ESP_ERR_INVALID_ARG;
        }
        expected_offset += (uint64_t)samples * 2u;
        if (expected_offset > size) {
            ESP_LOGE(TAG, "invalid sounds.bank: truncated payload id=%" PRIu32, id);
            return ESP_ERR_INVALID_SIZE;
        }
    }
    if (expected_offset != size) {
        ESP_LOGE(TAG, "invalid sounds.bank: trailing bytes");
        return ESP_ERR_INVALID_SIZE;
    }
    s_sound_count = count;
    return ESP_OK;
}

static void sound_entry(uint32_t sound_id, const uint8_t **pcm, uint32_t *samples) {
    const uint8_t *entry = bank_bytes() + APSB_HEADER_BYTES + sound_id * APSB_ENTRY_BYTES;
    *pcm = bank_bytes() + read_u32_le(entry);
    *samples = read_u32_le(entry + 4);
}

static int codec_volume(unsigned packed) {
    return (packed & OUTPUT_MUTED_BIT) != 0u ? 0 : (int)(packed & OUTPUT_VOLUME_MASK);
}

static void apply_desired_output(void) {
    const unsigned desired = atomic_load(&s_desired_output);
    if (desired == s_applied_output) {
        return;
    }
    bsp_audio_set_volume((uint8_t)codec_volume(desired));
    ESP_LOGI(TAG, "output volume=%u muted=%d",
             desired & OUTPUT_VOLUME_MASK,
             (desired & OUTPUT_MUTED_BIT) != 0u ? 1 : 0);
    s_applied_output = desired;
}

static int16_t clamp_i16(int32_t sample) {
    if (sample > INT16_MAX) return INT16_MAX;
    if (sample < INT16_MIN) return INT16_MIN;
    return (int16_t)sample;
}

static int collect_and_mix(int16_t output[SOUND_CHUNK_SAMPLES],
                           mixed_playback_t mixed[SOUND_PLAYBACK_SLOTS]) {
    int32_t accumulator[SOUND_CHUNK_SAMPLES] = {0};
    int mixed_count = 0;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    for (int slot_index = 0; slot_index < SOUND_PLAYBACK_SLOTS; ++slot_index) {
        const playback_slot_t slot = s_slots[slot_index];
        if (slot.state != SLOT_PLAYING) continue;
        const uint8_t *pcm;
        uint32_t sample_count;
        sound_entry(slot.sound_id, &pcm, &sample_count);
        uint32_t cursor = slot.cursor;
        bool ended = false;
        for (int frame = 0; frame < SOUND_CHUNK_SAMPLES; ++frame) {
            if (cursor >= sample_count) {
                if (!slot.looping) {
                    ended = true;
                    break;
                }
                cursor = 0;
            }
            accumulator[frame] += read_i16_le(pcm + cursor * 2u);
            ++cursor;
        }
        if (slot.looping && cursor >= sample_count) cursor = 0;
        mixed[mixed_count++] = (mixed_playback_t){
            .slot_index = slot_index,
            .handle = slot.handle,
            .cursor = slot.cursor,
            .next_cursor = cursor,
            .ended = ended || (!slot.looping && cursor >= sample_count),
        };
    }
    xSemaphoreGive(s_lock);
    for (int frame = 0; frame < SOUND_CHUNK_SAMPLES; ++frame) {
        output[frame] = clamp_i16(accumulator[frame]);
    }
    return mixed_count;
}

static void commit_mixed(const mixed_playback_t mixed[SOUND_PLAYBACK_SLOTS], int count) {
    xSemaphoreTake(s_lock, portMAX_DELAY);
    for (int i = 0; i < count; ++i) {
        playback_slot_t *slot = &s_slots[mixed[i].slot_index];
        if (slot->state == SLOT_FREE || slot->handle != mixed[i].handle ||
            slot->cursor != mixed[i].cursor) {
            continue;
        }
        if (mixed[i].ended) {
            slot->state = SLOT_FREE;
        } else {
            slot->cursor = mixed[i].next_cursor;
        }
    }
    xSemaphoreGive(s_lock);
}

static void sound_task(void *arg) {
    (void)arg;
    int16_t output[SOUND_CHUNK_SAMPLES];
    mixed_playback_t mixed[SOUND_PLAYBACK_SLOTS];
    TickType_t last_error_log = 0;
    for (;;) {
        xSemaphoreTake(s_io_lock, portMAX_DELAY);
        if (s_suspended) {
            xSemaphoreGive(s_io_lock);
            vTaskDelay(pdMS_TO_TICKS(SOUND_IDLE_DELAY_MS));
            continue;
        }
        apply_desired_output();
        const int count = collect_and_mix(output, mixed);
        if (count == 0) {
            xSemaphoreGive(s_io_lock);
            vTaskDelay(pdMS_TO_TICKS(SOUND_IDLE_DELAY_MS));
            continue;
        }
        const esp_err_t err = bsp_audio_write(output, sizeof(output));
        if (err == ESP_OK) {
            commit_mixed(mixed, count);
            xSemaphoreGive(s_io_lock);
            continue;
        }
        xSemaphoreGive(s_io_lock);
        const TickType_t now = xTaskGetTickCount();
        if ((now - last_error_log) >= pdMS_TO_TICKS(SOUND_ERROR_LOG_PERIOD_MS)) {
            last_error_log = now;
            ESP_LOGE(TAG, "mixed PCM write failed (%s); retrying", esp_err_to_name(err));
        }
        vTaskDelay(pdMS_TO_TICKS(SOUND_RETRY_DELAY_MS));
    }
}

static bool has_live_playback_unlocked(void) {
    for (int i = 0; i < SOUND_PLAYBACK_SLOTS; ++i) {
        if (s_slots[i].state != SLOT_FREE) return true;
    }
    return false;
}

static esp_err_t start_transport(void) {
    if (atomic_load(&s_started)) return ESP_OK;
    if (!atomic_load(&s_prepared)) {
        const esp_err_t prepare_err = ai_passport_sound_player_prepare(0, true);
        if (prepare_err != ESP_OK) return prepare_err;
    }

    s_lock = xSemaphoreCreateMutex();
    if (s_lock == NULL) return ESP_ERR_NO_MEM;
    s_io_lock = xSemaphoreCreateMutex();
    if (s_io_lock == NULL) {
        vSemaphoreDelete(s_lock);
        s_lock = NULL;
        return ESP_ERR_NO_MEM;
    }

    esp_err_t err = bsp_audio_init();
    if (err != ESP_OK) {
        vSemaphoreDelete(s_lock);
        vSemaphoreDelete(s_io_lock);
        s_lock = NULL;
        s_io_lock = NULL;
        return err;
    }
    err = bsp_audio_set_format(AI_PASSPORT_SOUND_SAMPLE_RATE_HZ,
                               AI_PASSPORT_SOUND_BITS_PER_SAMPLE,
                               AI_PASSPORT_SOUND_CHANNELS);
    if (err != ESP_OK) {
        vSemaphoreDelete(s_lock);
        vSemaphoreDelete(s_io_lock);
        s_lock = NULL;
        s_io_lock = NULL;
        return err;
    }

    s_applied_output = OUTPUT_UNAPPLIED;
    atomic_store(&s_started, true);
    if (xTaskCreate(sound_task, "sound_player", SOUND_TASK_STACK, NULL,
                    SOUND_TASK_PRIORITY, NULL) != pdPASS) {
        atomic_store(&s_started, false);
        vSemaphoreDelete(s_lock);
        vSemaphoreDelete(s_io_lock);
        s_lock = NULL;
        s_io_lock = NULL;
        return ESP_ERR_NO_MEM;
    }
    ESP_LOGI(TAG, "sound transport started entries=%" PRIu32 " slots=%d",
             s_sound_count, SOUND_PLAYBACK_SLOTS);
    return ESP_OK;
}

esp_err_t ai_passport_sound_player_prepare(int initial_volume, bool initial_muted) {
    if (atomic_load(&s_prepared)) return ESP_OK;
    const esp_err_t err = validate_bank();
    if (err != ESP_OK) return err;
    ai_passport_sound_set_output(initial_volume, initial_muted);
    atomic_store(&s_prepared, true);
    ESP_LOGI(TAG, "sound bank prepared entries=%" PRIu32 " bytes=%u",
             s_sound_count, (unsigned)bank_size());
    return ESP_OK;
}

esp_err_t ai_passport_sound_player_enable(void) {
    if (!atomic_load(&s_prepared)) {
        const esp_err_t err = ai_passport_sound_player_prepare(0, true);
        if (err != ESP_OK) return err;
    }
    atomic_store(&s_enabled, true);
    if (atomic_load(&s_started) || !has_live_playback_unlocked()) return ESP_OK;
    return start_transport();
}

void ai_passport_sound_player_suspend(void) {
    if (!atomic_load(&s_started)) return;
    xSemaphoreTake(s_io_lock, portMAX_DELAY);
    s_suspended = true;
    xSemaphoreGive(s_io_lock);
    ESP_LOGI(TAG, "playback task suspended for light sleep");
}

void ai_passport_sound_player_resume(void) {
    if (!atomic_load(&s_started)) return;
    xSemaphoreTake(s_io_lock, portMAX_DELAY);
    s_applied_output = OUTPUT_UNAPPLIED;
    s_suspended = false;
    xSemaphoreGive(s_io_lock);
    ESP_LOGI(TAG, "playback task resumed after light sleep");
}

void ai_passport_sound_set_output(int volume, bool muted) {
    if (volume < 0) volume = 0;
    if (volume > 100) volume = 100;
    unsigned packed = (unsigned)volume;
    if (muted) packed |= OUTPUT_MUTED_BIT;
    atomic_store(&s_desired_output, packed);
}

int32_t ai_passport_sound_play(int32_t sound_id, int32_t looping) {
    if (sound_id < 0) return -1;
    if (!atomic_load(&s_prepared)) {
        if (ai_passport_sound_player_prepare(0, true) != ESP_OK) return -1;
    }
    if ((uint32_t)sound_id >= s_sound_count) return -1;

    // Before app initialization completes there is deliberately no codec,
    // task, or mutex: constructor-time playback is staged in static slots.
    // Once enabled, the first play request lazily starts the transport.
    if (atomic_load(&s_enabled) && !atomic_load(&s_started)) {
        if (start_transport() != ESP_OK) return -1;
    }

    const bool locked = atomic_load(&s_started);
    if (locked) xSemaphoreTake(s_lock, portMAX_DELAY);
    int free_slot = -1;
    for (int i = 0; i < SOUND_PLAYBACK_SLOTS; ++i) {
        if (s_slots[i].state == SLOT_FREE) {
            free_slot = i;
            break;
        }
    }
    if (free_slot < 0) {
        if (locked) xSemaphoreGive(s_lock);
        return -1;
    }

    int32_t handle = -1;
    for (int attempt = 0; attempt <= SOUND_PLAYBACK_SLOTS; ++attempt) {
        const int32_t candidate = (int32_t)s_next_handle++;
        if (s_next_handle > INT32_MAX) s_next_handle = 1;
        bool collision = false;
        for (int i = 0; i < SOUND_PLAYBACK_SLOTS; ++i) {
            if (s_slots[i].state != SLOT_FREE && s_slots[i].handle == candidate) {
                collision = true;
                break;
            }
        }
        if (!collision) {
            handle = candidate;
            break;
        }
    }
    if (handle < 0) {
        if (locked) xSemaphoreGive(s_lock);
        return -1;
    }
    s_slots[free_slot] = (playback_slot_t){
        .handle = handle,
        .sound_id = (uint32_t)sound_id,
        .cursor = 0,
        .looping = looping != 0,
        .state = SLOT_PLAYING,
    };
    if (locked) xSemaphoreGive(s_lock);
    return handle;
}

static void set_slot_state(int32_t handle, slot_state_t expected, slot_state_t next) {
    if (handle <= 0) return;
    const bool locked = atomic_load(&s_started);
    if (locked) xSemaphoreTake(s_lock, portMAX_DELAY);
    for (int i = 0; i < SOUND_PLAYBACK_SLOTS; ++i) {
        if (s_slots[i].handle == handle && s_slots[i].state == expected) {
            s_slots[i].state = next;
            break;
        }
    }
    if (locked) xSemaphoreGive(s_lock);
}

void ai_passport_sound_pause(int32_t handle) {
    set_slot_state(handle, SLOT_PLAYING, SLOT_PAUSED);
}

void ai_passport_sound_resume(int32_t handle) {
    set_slot_state(handle, SLOT_PAUSED, SLOT_PLAYING);
}

void ai_passport_sound_stop(int32_t handle) {
    if (handle <= 0) return;
    const bool locked = atomic_load(&s_started);
    if (locked) xSemaphoreTake(s_lock, portMAX_DELAY);
    for (int i = 0; i < SOUND_PLAYBACK_SLOTS; ++i) {
        if (s_slots[i].handle == handle && s_slots[i].state != SLOT_FREE) {
            s_slots[i].state = SLOT_FREE;
            break;
        }
    }
    if (locked) xSemaphoreGive(s_lock);
}

int64_t ai_passport_sound_position_us(int32_t handle) {
    if (handle <= 0) return -1;
    int64_t position = -1;
    const bool locked = atomic_load(&s_started);
    if (locked) xSemaphoreTake(s_lock, portMAX_DELAY);
    for (int i = 0; i < SOUND_PLAYBACK_SLOTS; ++i) {
        if (s_slots[i].handle == handle && s_slots[i].state != SLOT_FREE) {
            position = (int64_t)s_slots[i].cursor * 1000000LL /
                       AI_PASSPORT_SOUND_SAMPLE_RATE_HZ;
            break;
        }
    }
    if (locked) xSemaphoreGive(s_lock);
    return position;
}
