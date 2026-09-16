// Host-only native test linker stubs. Device firmware links the real C
// bridges of the folotoy-ai-passport Host (display bridge, battery bridge,
// music transport, clock bridge) instead.
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

// Host transport stand-ins: both clocks and the availability fact are
// frozen at "no music, no time" so the host-side runtime tests stay
// deterministic unless a test drives them through the setters below.
static int32_t s_test_music_available;
static int64_t s_test_music_position;
static int64_t s_test_now_us;

int32_t ai_passport_music_available(void) { return s_test_music_available; }

int64_t ai_passport_music_position_us(void) { return s_test_music_position; }

int64_t ai_passport_now_us(void) { return s_test_now_us; }

void ai_passport_test_set_music_available(int32_t available) {
    s_test_music_available = available;
}

void ai_passport_test_set_music_position(int64_t position_us) {
    s_test_music_position = position_us;
}

void ai_passport_test_set_now_us(int64_t now_us) { s_test_now_us = now_us; }

// Recording stand-in for the music transport's absolute output setter. The
// device firmware's music_stream owns the real one; host tests read what
// the device adapter requested through the probes below. No control
// arithmetic lives here — the stub only records the facts it was handed.
static int32_t s_last_output_volume;
static int32_t s_last_output_muted;
static int32_t s_output_set_calls;

void ai_passport_music_set_output(int32_t volume, int32_t muted) {
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
