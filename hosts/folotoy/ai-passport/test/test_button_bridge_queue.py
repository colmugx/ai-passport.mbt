"""Host unit test for the device button-bridge event queue.

Compiles the firmware's real main/button_bridge.c on the
host C compiler against a faithful shim of the tiny BSP/FreeRTOS surface it
uses (bounded queue + callback registration), and drives the actual callback
the way the shared esp_timer task would. Proves:

  * the queue is created with the agreed bound of 8 events
  * the callback path is non-blocking (every enqueue uses zero wait)
  * PRESS/CLICK/DOUBLE/LONG all enter the queue with their exact event kind
  * UP/DOWN/OK map to the device-neutral codes 0/1/2, drained FIFO
  * a full queue drops the event and increments the bridge's own counter

No ADC hardware is emulated: the BSP driver itself stays vendored upstream.
"""

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HOST_ROOT = Path(__file__).resolve().parent.parent
COMPONENT = HOST_ROOT / "main"

# Faithful shims of the exact surface button_bridge.c consumes. The BSP
# signatures mirror the pinned external FoloToy BSP include/
# bsp_button.h; the queue mirrors FreeRTOS bounded-FIFO semantics with the
# zero-wait behavior the callback contract requires.
SHIM_HEADERS = {
    "esp_err.h": r"""
#pragma once
#include <stdint.h>
typedef int esp_err_t;
#define ESP_OK 0
#define ESP_ERR_NO_MEM 0x101
""",
    "esp_log.h": r"""
#pragma once
// Host no-ops that still consume the tag, matching real usage patterns.
#define ESP_LOGE(tag, ...) do { (void)(tag); } while (0)
#define ESP_LOGI(tag, ...) do { (void)(tag); } while (0)
#define ESP_LOGW(tag, ...) do { (void)(tag); } while (0)
""",
    "bsp_button.h": r"""
#pragma once
#include "esp_err.h"
typedef enum {
    BSP_BTN_UP = 0,
    BSP_BTN_DOWN,
    BSP_BTN_OK,
} bsp_btn_t;
typedef enum {
    BSP_BTN_PRESS = 0,
    BSP_BTN_CLICK,
    BSP_BTN_DOUBLE,
    BSP_BTN_LONG,
} bsp_btn_ev_t;
typedef void (*bsp_btn_cb_t)(bsp_btn_t btn, bsp_btn_ev_t ev, void *user);
esp_err_t bsp_button_init(bsp_btn_cb_t cb, void *user);
""",
    "freertos/FreeRTOS.h": r"""
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#define pdTRUE 1
#define pdFALSE 0
typedef uint32_t TickType_t;
#define pdMS_TO_TICKS(ms) ((TickType_t)(ms))
""",
    "freertos/queue.h": r"""
#pragma once
#include "FreeRTOS.h"

struct fake_queue {
    size_t capacity;
    size_t item_size;
    size_t count;
    size_t head;
    char *slots;
};
typedef struct fake_queue *QueueHandle_t;

// Facts the host test asserts on: the created bound and every send's wait.
extern size_t shim_last_queue_length;
extern int shim_last_send_ticks;
extern int shim_send_blocking_violation;

static inline QueueHandle_t xQueueCreate(size_t length, size_t item_size) {
    struct fake_queue *queue = malloc(sizeof(*queue));
    if (queue == NULL) {
        return NULL;
    }
    queue->slots = malloc(length * item_size);
    if (queue->slots == NULL) {
        free(queue);
        return NULL;
    }
    queue->capacity = length;
    queue->item_size = item_size;
    queue->count = 0;
    queue->head = 0;
    shim_last_queue_length = length;
    return queue;
}

// Bounded FIFO send: like FreeRTOS, a zero-tick send never blocks — a full
// queue returns pdFALSE immediately.
static inline int xQueueSend(QueueHandle_t queue, const void *item,
                             TickType_t ticks) {
    shim_last_send_ticks = (int)ticks;
    if (ticks != 0) {
        shim_send_blocking_violation += 1;
    }
    if (queue == NULL || queue->count == queue->capacity) {
        return pdFALSE;
    }
    const size_t tail = (queue->head + queue->count) % queue->capacity;
    __builtin_memcpy(queue->slots + tail * queue->item_size, item,
                     queue->item_size);
    queue->count += 1;
    return pdTRUE;
}

static inline int xQueueReceive(QueueHandle_t queue, void *out,
                                TickType_t ticks) {
    if (queue == NULL || queue->count == 0) {
        return pdFALSE;
    }
    __builtin_memcpy(out, queue->slots + queue->head * queue->item_size,
                     queue->item_size);
    queue->head = (queue->head + 1) % queue->capacity;
    queue->count -= 1;
    return pdTRUE;
}
""",
}

# Registration shim so the test can invoke the real callback; the queue
# implementation records nothing extra.
SHIM_SOURCES = {
    "shim_bsp_button.c": r"""
#include <stddef.h>

#include "bsp_button.h"

bsp_btn_cb_t shim_registered_cb;
void *shim_registered_user;

// Definitions for the facts recorded by the queue shim (freertos/queue.h).
size_t shim_last_queue_length;
int shim_last_send_ticks;
int shim_send_blocking_violation;

esp_err_t bsp_button_init(bsp_btn_cb_t cb, void *user) {
    if (cb == NULL) {
        return 0x102;  // ESP_ERR_INVALID_ARG-shaped failure
    }
    shim_registered_cb = cb;
    shim_registered_user = user;
    return ESP_OK;
}
""",
}

HARNESS = r"""
#include <assert.h>
#include <stdio.h>

#include "bsp_button.h"
#include "button_bridge.h"

extern bsp_btn_cb_t shim_registered_cb;
extern void *shim_registered_user;
extern size_t shim_last_queue_length;
extern int shim_last_send_ticks;
extern int shim_send_blocking_violation;

static void press(bsp_btn_t button, bsp_btn_ev_t event) {
    shim_registered_cb(button, event, shim_registered_user);
}

int main(void) {
    // Init creates the bounded queue (8 events) and registers the callback.
    assert(ai_passport_button_bridge_init() == ESP_OK);
    assert(shim_last_queue_length == 8);
    assert(shim_registered_cb != NULL);

    ai_passport_button_event_t item;
    assert(ai_passport_button_bridge_poll(&item) == false);

    // PRESS maps UP/DOWN/OK to the neutral codes 0/1/2, drained FIFO.
    press(BSP_BTN_UP, BSP_BTN_PRESS);
    press(BSP_BTN_DOWN, BSP_BTN_PRESS);
    press(BSP_BTN_OK, BSP_BTN_PRESS);
    assert(ai_passport_button_bridge_poll(&item) == true);
    assert(item.button == AI_PASSPORT_BTN_UP && item.kind == AI_PASSPORT_EVENT_PRESS);
    assert(ai_passport_button_bridge_poll(&item) == true);
    assert(item.button == AI_PASSPORT_BTN_DOWN && item.kind == AI_PASSPORT_EVENT_PRESS);
    assert(ai_passport_button_bridge_poll(&item) == true);
    assert(item.button == AI_PASSPORT_BTN_OK && item.kind == AI_PASSPORT_EVENT_PRESS);
    assert(ai_passport_button_bridge_poll(&item) == false);

    // All recognized BSP events retain their kind and callback order.
    press(BSP_BTN_UP, BSP_BTN_CLICK);
    press(BSP_BTN_UP, BSP_BTN_DOUBLE);
    press(BSP_BTN_UP, BSP_BTN_LONG);
    assert(ai_passport_button_bridge_poll(&item) == true);
    assert(item.button == AI_PASSPORT_BTN_UP && item.kind == AI_PASSPORT_EVENT_CLICK);
    assert(ai_passport_button_bridge_poll(&item) == true);
    assert(item.button == AI_PASSPORT_BTN_UP && item.kind == AI_PASSPORT_EVENT_DOUBLE_CLICK);
    assert(ai_passport_button_bridge_poll(&item) == true);
    assert(item.button == AI_PASSPORT_BTN_UP && item.kind == AI_PASSPORT_EVENT_LONG_PRESS);
    assert(ai_passport_button_bridge_poll(&item) == false);
    assert(ai_passport_button_dropped_events() == 0);

    // Every callback enqueue was a zero-wait send: the callback path never
    // blocks.
    assert(shim_send_blocking_violation == 0);
    assert(shim_last_send_ticks == 0);

    // Bounded: eight events fit, the ninth is dropped by the bridge and
    // counted by the bridge.
    for (int i = 0; i < 8; i++) {
        press(BSP_BTN_UP, BSP_BTN_PRESS);
    }
    assert(ai_passport_button_dropped_events() == 0);
    press(BSP_BTN_OK, BSP_BTN_PRESS);
    assert(ai_passport_button_dropped_events() == 1);
    int drained = 0;
    while (ai_passport_button_bridge_poll(&item)) {
        assert(item.button == AI_PASSPORT_BTN_UP);
        assert(item.kind == AI_PASSPORT_EVENT_PRESS);
        drained += 1;
    }
    assert(drained == 8);
    assert(ai_passport_button_dropped_events() == 1);

    puts("ok");
    return 0;
}
"""


class ButtonBridgeQueueTests(unittest.TestCase):
    def setUp(self):
        if shutil.which("cc") is None:
            self.skipTest("host C compiler is not installed")

    def test_queue_behavior(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            shim = root / "shim"
            for relative, content in SHIM_HEADERS.items():
                path = shim / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
            for name, content in SHIM_SOURCES.items():
                (shim / name).write_text(content)
            harness = root / "harness.c"
            harness.write_text(HARNESS)
            binary = root / "test"
            compile_result = subprocess.run(
                [
                    "cc", "-std=c11", "-Wall", "-Werror",
                    "-I", str(shim),
                    "-I", str(COMPONENT),
                    str(shim / "shim_bsp_button.c"),
                    str(COMPONENT / "button_bridge.c"),
                    str(harness),
                    "-o", str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                compile_result.returncode, 0, compile_result.stderr or "compile failed"
            )
            run_result = subprocess.run(
                [str(binary)], capture_output=True, text=True
            )
            self.assertEqual(run_result.returncode, 0, run_result.stdout)
            self.assertIn("ok", run_result.stdout)


if __name__ == "__main__":
    unittest.main()
