"""Executable regression for non-blocking FoloToy microphone stop.

The real component is compiled against small FreeRTOS/BSP shims. The harness
enters capture_task until bsp_audio_read() simulates an indefinitely blocked
RX call, then verifies capture_stop() returns without waiting on that read.
"""

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HOST_ROOT = Path(__file__).resolve().parent.parent
COMPONENT = HOST_ROOT / "main"

HEADERS = {
    "esp_err.h": r"""
#pragma once
typedef int esp_err_t;
#define ESP_OK 0
#define ESP_ERR_NO_MEM 0x101
const char *esp_err_to_name(esp_err_t err);
""",
    "esp_log.h": r"""
#pragma once
#define ESP_LOGE(tag, ...) do { (void)(tag); } while (0)
#define ESP_LOGI(tag, ...) do { (void)(tag); } while (0)
""",
    "bsp_audio.h": r"""
#pragma once
#include <stddef.h>
#include "esp_err.h"
esp_err_t bsp_audio_init(void);
esp_err_t bsp_audio_set_format(int rate, int bits, int channels);
esp_err_t bsp_audio_read(void *bytes, size_t length);
""",
    "freertos/FreeRTOS.h": r"""
#pragma once
#include <stdint.h>
typedef int BaseType_t;
typedef uint32_t TickType_t;
#define pdPASS 1
#define pdTRUE 1
#define portMAX_DELAY UINT32_MAX
#define tskIDLE_PRIORITY 0
#define pdMS_TO_TICKS(ms) ((TickType_t)(ms))
""",
    "freertos/task.h": r"""
#pragma once
#include "FreeRTOS.h"
typedef void (*TaskFunction_t)(void *);
typedef void *TaskHandle_t;
BaseType_t xTaskCreate(TaskFunction_t task, const char *name, unsigned stack,
                       void *arg, unsigned priority, TaskHandle_t *handle);
void vTaskDelay(TickType_t ticks);
""",
    "freertos/semphr.h": r"""
#pragma once
#include "FreeRTOS.h"
typedef struct fake_mutex *SemaphoreHandle_t;
SemaphoreHandle_t xSemaphoreCreateMutex(void);
BaseType_t xSemaphoreTake(SemaphoreHandle_t lock, TickType_t ticks);
BaseType_t xSemaphoreGive(SemaphoreHandle_t lock);
""",
}

SHIM = r"""
#include <assert.h>
#include <setjmp.h>
#include <stdint.h>
#include <string.h>

#include "bsp_audio.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

struct fake_mutex { int held; };
static struct fake_mutex mutex;
TaskFunction_t shim_task;
jmp_buf shim_read_blocked;

const char *esp_err_to_name(esp_err_t err) { (void)err; return "shim"; }
esp_err_t bsp_audio_init(void) { return ESP_OK; }
esp_err_t bsp_audio_set_format(int rate, int bits, int channels) {
    assert(rate == 16000 && bits == 16 && channels == 1);
    return ESP_OK;
}
esp_err_t bsp_audio_read(void *bytes, size_t length) {
    (void)bytes;
    assert(length == 240u * sizeof(int16_t));
    longjmp(shim_read_blocked, 1);
}
SemaphoreHandle_t xSemaphoreCreateMutex(void) { return &mutex; }
BaseType_t xSemaphoreTake(SemaphoreHandle_t lock, TickType_t ticks) {
    (void)ticks;
    assert(lock == &mutex && !lock->held);
    lock->held = 1;
    return pdTRUE;
}
BaseType_t xSemaphoreGive(SemaphoreHandle_t lock) {
    assert(lock == &mutex && lock->held);
    lock->held = 0;
    return pdTRUE;
}
BaseType_t xTaskCreate(TaskFunction_t task, const char *name, unsigned stack,
                       void *arg, unsigned priority, TaskHandle_t *handle) {
    (void)arg;
    assert(strcmp(name, "microphone") == 0);
    assert(stack == 3072 && priority == 1);
    shim_task = task;
    if (handle) *handle = (void *)1;
    return pdPASS;
}
void vTaskDelay(TickType_t ticks) { assert(ticks > 0); }
"""

HARNESS = r"""
#include <assert.h>
#include <setjmp.h>
#include <stdio.h>

#include "microphone_bridge.h"

extern void (*shim_task)(void *);
extern jmp_buf shim_read_blocked;

int main(void) {
    assert(ai_passport_mic_start() == 3);
    assert(ai_passport_mic_status() == 3);
    assert(shim_task != 0);

    if (setjmp(shim_read_blocked) == 0) {
        shim_task(NULL);
        assert(!"capture task should have entered the simulated blocking read");
    }

    // RX is now logically still in flight. The regression is that stop must
    // return immediately instead of waiting forever for that physical read.
    ai_passport_mic_stop();
    assert(ai_passport_mic_status() == 1);
    assert(ai_passport_mic_wait_idle(0) == false);

    puts("microphone-stop-ok");
    return 0;
}
"""


class MicrophoneBridgeTest(unittest.TestCase):
    def test_stop_does_not_wait_for_blocked_rx(self):
        compiler = shutil.which("clang") or shutil.which("cc")
        self.assertIsNotNone(compiler, "a host C compiler is required")
        with tempfile.TemporaryDirectory(prefix="passport-microphone-") as raw:
            root = Path(raw)
            include = root / "include"
            (include / "freertos").mkdir(parents=True)
            for name, body in HEADERS.items():
                target = include / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(body)
            (root / "shim.c").write_text(SHIM)
            (root / "harness.c").write_text(HARNESS)
            executable = root / "microphone-test"
            compile_result = subprocess.run(
                [
                    compiler,
                    "-std=c11",
                    "-Wall",
                    "-Wextra",
                    "-Werror",
                    f"-I{include}",
                    f"-I{COMPONENT}",
                    str(COMPONENT / "microphone_bridge.c"),
                    str(root / "shim.c"),
                    str(root / "harness.c"),
                    "-o",
                    str(executable),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            run = subprocess.run([executable], text=True, capture_output=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(run.stdout.strip(), "microphone-stop-ok")


if __name__ == "__main__":
    unittest.main()
