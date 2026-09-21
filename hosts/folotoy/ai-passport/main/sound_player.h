#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#define AI_PASSPORT_SOUND_SAMPLE_RATE_HZ 16000
#define AI_PASSPORT_SOUND_CHANNELS 1
#define AI_PASSPORT_SOUND_BITS_PER_SAMPLE 16

// Initializes the codec, validates the embedded APSB bank, and starts the
// single task that owns PCM writes and codec-volume changes. An empty bank is
// valid. Idempotent after a successful start.
esp_err_t ai_passport_sound_player_start(int initial_volume, bool initial_muted);
// Quiesces PCM writes before BSP codec sleep, preserving playback positions.
void ai_passport_sound_player_suspend(void);
void ai_passport_sound_player_resume(void);

// Publishes the application master-output state. The audio task applies the
// latest coherent volume/mute pair; redundant states do not touch the codec.
void ai_passport_sound_set_output(int volume, bool muted);

// Internal native Host ABI. A positive value is a unique live playback
// handle; -1 means invalid sound, unavailable player, or exhausted slots.
int32_t ai_passport_sound_play(int32_t sound_id, int32_t looping);
void ai_passport_sound_pause(int32_t handle);
void ai_passport_sound_resume(int32_t handle);
void ai_passport_sound_stop(int32_t handle);
// Returns microseconds for a live playback and -1 for an invalid/dead handle.
int64_t ai_passport_sound_position_us(int32_t handle);
