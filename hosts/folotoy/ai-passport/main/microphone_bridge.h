// Bounded PCM16 microphone transport for the portable audio capture API.
#pragma once

#include <stdbool.h>
#include <stdint.h>

// Status wire codes: 0 unavailable, 1 idle, 2 requesting, 3 recording,
// 4 permission denied, 5 failed. Physical capture starts synchronously.
int32_t ai_passport_mic_start(void);
int32_t ai_passport_mic_status(void);
void ai_passport_mic_stop(void);
// Waits only for an already in-flight physical RX read to return. Ordinary
// capture_stop() is intentionally non-blocking; power transitions use this
// bounded barrier before reconfiguring the shared codec/I2S transport.
bool ai_passport_mic_wait_idle(uint32_t timeout_ms);
int32_t ai_passport_mic_read(int32_t *out, int32_t capacity);
int32_t ai_passport_mic_dropped_samples(void);
