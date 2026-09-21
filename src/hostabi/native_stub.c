// Host-only native test linker stubs. Device firmware links the real C
// bridges of the folotoy-ai-passport Host (display bridge, battery bridge,
// sound runtime, clock bridge) instead.
// Calling a display stub means the device display bridge was not linked as
// intended; the battery stub honestly reports "unavailable" because host
// builds have no gauge attached, which exercises the unknown-reading path.
#include <stdint.h>
#include <stdlib.h>

void ai_passport_display_begin(void) { abort(); }
void ai_passport_display_row(int32_t y, int32_t *row) {
    (void)y;
    (void)row;
    abort();
}
void ai_passport_display_end(void) { abort(); }

int32_t ai_passport_battery_soc(void) { return -1; }

static int64_t s_test_now_us;

int64_t ai_passport_now_us(void) { return s_test_now_us; }

void ai_passport_test_set_now_us(int64_t now_us) { s_test_now_us = now_us; }

// Recording stand-in for the sound runtime's absolute output setter. The
// device firmware's sound_player owns the real one; host tests read what
// the device adapter requested through the probes below. No control
// arithmetic lives here — the stub only records the facts it was handed.
static int32_t s_last_output_volume;
static int32_t s_last_output_muted;
static int32_t s_output_set_calls;

void ai_passport_sound_set_output(int32_t volume, int32_t muted) {
    s_last_output_volume = volume;
    s_last_output_muted = muted;
    s_output_set_calls += 1;
}

int32_t ai_passport_test_last_output_volume(void) {
    return s_last_output_volume;
}

int32_t ai_passport_test_last_output_muted(void) {
    return s_last_output_muted;
}

int32_t ai_passport_test_output_set_calls(void) { return s_output_set_calls; }

static int32_t s_next_sound_handle = 1;

int32_t ai_passport_sound_play(int32_t sound_id, int32_t looping) {
    (void)sound_id;
    (void)looping;
    return s_next_sound_handle++;
}

void ai_passport_sound_pause(int32_t handle) { (void)handle; }

void ai_passport_sound_resume(int32_t handle) { (void)handle; }

void ai_passport_sound_stop(int32_t handle) { (void)handle; }

int64_t ai_passport_sound_position_us(int32_t handle) {
    return handle > 0 ? (int64_t)handle * 1000LL : -1LL;
}

// Host-side native tests have no physical microphone. A capture attempt
// remains explicitly unavailable and cannot silently return blank audio.
int32_t ai_passport_mic_start(void) { return 0; }
int32_t ai_passport_mic_status(void) { return 0; }
void ai_passport_mic_stop(void) {}
int32_t ai_passport_mic_read(int32_t *out, int32_t capacity) {
    (void)out;
    (void)capacity;
    abort();
}
int32_t ai_passport_mic_dropped_samples(void) { return 0; }
