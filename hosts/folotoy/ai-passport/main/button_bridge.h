// Button bridge: input delivery for the official FoloToy ADC button driver
// (UP / DOWN / OK on one shared GPIO0/ADC1_CH0 line). The bridge owns the
// bounded raw press-event queue and nothing else: the codes it delivers are
// device-neutral facts with no volume/mute meaning — the portable MoonBit
// App decides what a physical press does.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

// Device-neutral physical button codes. Values are fixed by the C ABI with
// the MoonBit input export (src/device/input_bridge.mbt): 0 = Up, 1 = Down,
// 2 = Ok. Unknown codes are ignored there.
typedef enum {
    AI_PASSPORT_BTN_UP = 0,
    AI_PASSPORT_BTN_DOWN = 1,
    AI_PASSPORT_BTN_OK = 2,
} ai_passport_button_t;

// Raw press events held by the bridge. Small on purpose: a human cannot
// outrun the frame task draining one event per frame (about 33 ms); a full
// queue means repeated presses stacked up and dropping the tail is the
// desired behavior.
#define BUTTON_EVENT_QUEUE_LENGTH 8

// Registers the button callback with the BSP and creates the event queue.
// The callback runs in the button component's shared esp_timer task and
// only ever performs a zero-wait enqueue. Never blocks; a failure only
// disables the controls — the caller keeps the application and music running.
esp_err_t ai_passport_button_bridge_init(void);

// Drains at most one queued physical press into *out. Frame-task only:
// call it at most once per rendered frame so one queued press maps to
// exactly one application action. Returns false when no event is queued.
bool ai_passport_button_bridge_poll(ai_passport_button_t *out);

// Press events dropped because the queue was full (or the bridge was never
// initialized). Owned by this component: input delivery is the only thing
// that can drop a button event.
uint32_t ai_passport_button_dropped_events(void);
