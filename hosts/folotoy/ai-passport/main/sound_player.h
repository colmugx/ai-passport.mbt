#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#define AI_PASSPORT_SOUND_SAMPLE_RATE_HZ 16000
#define AI_PASSPORT_SOUND_CHANNELS 1
#define AI_PASSPORT_SOUND_BITS_PER_SAMPLE 16

// Validates the embedded APSB bank and publishes the initial master-output
// state without allocating codec, I2S, mutex, or task resources. This is safe
// to call before application construction so large application allocations
// happen before optional audio transport fragments internal RAM.
esp_err_t ai_passport_sound_player_prepare(int initial_volume, bool initial_muted);

// Marks the post-application-init boundary. Constructor-time play() requests
// are staged in static slots and start the transport here; otherwise codec,
// I2S, mutexes, and the playback task remain unallocated until the first play().
esp_err_t ai_passport_sound_player_enable(void);
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
