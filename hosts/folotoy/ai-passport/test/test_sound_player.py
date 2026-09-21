"""Executable host test for the device APSB sound player.

Compiles the real firmware component against small ESP-IDF/FreeRTOS shims.
The captured audio task renders one committed chunk, proving independent
handles, overlap mixing with PCM16 saturation, loop positions, one-shot
retirement, slot exhaustion, pause/resume/stop, and master output delivery.
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
#define ESP_ERR_INVALID_ARG 0x102
#define ESP_ERR_INVALID_SIZE 0x104
#define ESP_ERR_NOT_SUPPORTED 0x106
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
#include <stdint.h>
#include "esp_err.h"
esp_err_t bsp_audio_init(void);
esp_err_t bsp_audio_set_format(int rate, int bits, int channels);
void bsp_audio_set_volume(uint8_t volume);
esp_err_t bsp_audio_write(const void *bytes, size_t length);
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
BaseType_t xTaskCreate(TaskFunction_t task, const char *name, unsigned stack,
                       void *arg, unsigned priority, void *handle);
void vTaskDelay(TickType_t ticks);
TickType_t xTaskGetTickCount(void);
""",
    "freertos/semphr.h": r"""
#pragma once
#include "FreeRTOS.h"
typedef struct fake_mutex *SemaphoreHandle_t;
SemaphoreHandle_t xSemaphoreCreateMutex(void);
BaseType_t xSemaphoreTake(SemaphoreHandle_t lock, TickType_t ticks);
BaseType_t xSemaphoreGive(SemaphoreHandle_t lock);
void vSemaphoreDelete(SemaphoreHandle_t lock);
""",
}

SHIM = r"""
#include <assert.h>
#include <setjmp.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "bsp_audio.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

// APSB v1: two four-sample sounds. The symbols match ESP-IDF's
// target_add_binary_data(... RENAME_TO sounds_bank) output.
__asm__(
    ".global _binary_sounds_bank_start\n"
    "_binary_sounds_bank_start:\n"
    ".byte 0x41,0x50,0x53,0x42, 1,0, 16,0, 2,0,0,0, 8,0, 0,0\n"
    ".byte 32,0,0,0, 4,0,0,0, 40,0,0,0, 4,0,0,0\n"
    ".short 10000,10000,-10000,-10000\n"
    ".short 30000,30000,30000,30000\n"
    ".global _binary_sounds_bank_end\n"
    "_binary_sounds_bank_end:\n"
);

struct fake_mutex { int held; };
static struct fake_mutex mutexes[2];
static int mutex_count;
TaskFunction_t shim_task;
int16_t shim_first_chunk[240];
int shim_write_calls;
int shim_codec_volume = -1;
static jmp_buf task_exit;

const char *esp_err_to_name(esp_err_t err) { (void)err; return "shim"; }
esp_err_t bsp_audio_init(void) { return ESP_OK; }
esp_err_t bsp_audio_set_format(int rate, int bits, int channels) {
    assert(rate == 16000 && bits == 16 && channels == 1);
    return ESP_OK;
}
void bsp_audio_set_volume(uint8_t volume) {
    shim_codec_volume = volume;
}
esp_err_t bsp_audio_write(const void *bytes, size_t length) {
    assert(length == sizeof(shim_first_chunk));
    if (shim_write_calls++ == 0) {
        memcpy(shim_first_chunk, bytes, length);
        return ESP_OK;
    }
    longjmp(task_exit, 1);
}
SemaphoreHandle_t xSemaphoreCreateMutex(void) {
    assert(mutex_count < 2);
    return &mutexes[mutex_count++];
}
BaseType_t xSemaphoreTake(SemaphoreHandle_t lock, TickType_t ticks) {
    (void)ticks;
    assert(lock >= mutexes && lock < mutexes + 2 && !lock->held);
    lock->held = 1;
    return pdTRUE;
}
BaseType_t xSemaphoreGive(SemaphoreHandle_t lock) {
    assert(lock >= mutexes && lock < mutexes + 2 && lock->held);
    lock->held = 0;
    return pdTRUE;
}
void vSemaphoreDelete(SemaphoreHandle_t lock) { assert(lock >= mutexes && lock < mutexes + 2); }
BaseType_t xTaskCreate(TaskFunction_t task, const char *name, unsigned stack,
                       void *arg, unsigned priority, void *handle) {
    (void)arg; (void)handle;
    assert(strcmp(name, "sound_player") == 0);
    assert(stack == 4096 && priority == 2);
    shim_task = task;
    return pdPASS;
}
void vTaskDelay(TickType_t ticks) { assert(ticks > 0); }
TickType_t xTaskGetTickCount(void) { return 1000; }

void shim_run_one_committed_chunk(void) {
    if (setjmp(task_exit) == 0) shim_task(NULL);
}
"""

EMPTY_SHIM = SHIM.replace(
    r'''    ".byte 0x41,0x50,0x53,0x42, 1,0, 16,0, 2,0,0,0, 8,0, 0,0\n"
    ".byte 32,0,0,0, 4,0,0,0, 40,0,0,0, 4,0,0,0\n"
    ".short 10000,10000,-10000,-10000\n"
    ".short 30000,30000,30000,30000\n"''',
    r'''    ".byte 0x41,0x50,0x53,0x42, 1,0, 16,0, 0,0,0,0, 8,0, 0,0\n"''',
)

TRAILING_SHIM = EMPTY_SHIM.replace(
    r'''    ".global _binary_sounds_bank_end\n"''',
    r'''    ".byte 0\n"
    ".global _binary_sounds_bank_end\n"''',
)

HARNESS = r"""
#include <assert.h>
#include <stdint.h>
#include <stdio.h>

#include "sound_player.h"

extern int16_t shim_first_chunk[240];
extern int shim_write_calls;
extern int shim_codec_volume;
void shim_run_one_committed_chunk(void);

int main(void) {
    assert(ai_passport_sound_player_start(0, true) == ESP_OK);
    assert(ai_passport_sound_player_start(80, false) == ESP_OK);
    assert(ai_passport_sound_play(-1, 0) == -1);
    assert(ai_passport_sound_play(2, 0) == -1);

    const int32_t loop_a = ai_passport_sound_play(0, 1);
    const int32_t loop_b = ai_passport_sound_play(0, 1);
    const int32_t one_shot = ai_passport_sound_play(1, 0);
    assert(loop_a > 0 && loop_b > 0 && one_shot > 0);
    assert(loop_a != loop_b && loop_a != one_shot && loop_b != one_shot);
    const int32_t fourth = ai_passport_sound_play(0, 1);
    assert(fourth > 0);
    assert(ai_passport_sound_play(0, 1) == -1);
    ai_passport_sound_stop(fourth);

    ai_passport_sound_set_output(173, false);
    shim_run_one_committed_chunk();
    assert(shim_write_calls == 2);
    assert(shim_codec_volume == 100);
    // Two copies of sound 0 plus sound 1. The first pair saturates; once the
    // one-shot ends, only the two looping copies remain.
    assert(shim_first_chunk[0] == 32767);
    assert(shim_first_chunk[1] == 32767);
    assert(shim_first_chunk[2] == 10000);
    assert(shim_first_chunk[3] == 10000);
    assert(shim_first_chunk[4] == 20000);
    assert(shim_first_chunk[6] == -20000);

    assert(ai_passport_sound_position_us(loop_a) == 0);
    assert(ai_passport_sound_position_us(loop_b) == 0);
    assert(ai_passport_sound_position_us(one_shot) == -1);
    ai_passport_sound_pause(loop_a);
    assert(ai_passport_sound_position_us(loop_a) == 0);
    ai_passport_sound_resume(loop_a);
    assert(ai_passport_sound_position_us(loop_a) == 0);
    ai_passport_sound_stop(loop_a);
    assert(ai_passport_sound_position_us(loop_a) == -1);
    assert(ai_passport_sound_position_us(loop_b) == 0);

    puts("sound-player-ok");
    return 0;
}
"""

EMPTY_HARNESS = r"""
#include <assert.h>
#include <stdio.h>
#include "sound_player.h"

int main(void) {
    assert(ai_passport_sound_player_start(0, true) == ESP_OK);
    assert(ai_passport_sound_play(0, 0) == -1);
    puts("empty-sound-bank-ok");
    return 0;
}
"""

INVALID_HARNESS = r"""
#include <assert.h>
#include <stdio.h>
#include "sound_player.h"

int main(void) {
    assert(ai_passport_sound_player_start(0, true) == ESP_ERR_INVALID_SIZE);
    assert(ai_passport_sound_play(0, 0) == -1);
    puts("invalid-sound-bank-rejected");
    return 0;
}
"""


class SoundPlayerTest(unittest.TestCase):
    def compile_and_run(self, shim, harness, expected):
        compiler = shutil.which("clang") or shutil.which("cc")
        self.assertIsNotNone(compiler, "a host C compiler is required")
        with tempfile.TemporaryDirectory(prefix="passport-sound-player-") as raw:
            root = Path(raw)
            include = root / "include"
            (include / "freertos").mkdir(parents=True)
            for name, body in HEADERS.items():
                target = include / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(body)
            (root / "shim.c").write_text(shim)
            (root / "harness.c").write_text(harness)
            executable = root / "sound-player-test"
            compile_result = subprocess.run(
                [
                    compiler,
                    "-std=c11",
                    "-Wall",
                    "-Wextra",
                    "-Werror",
                    f"-I{include}",
                    f"-I{COMPONENT}",
                    str(COMPONENT / "sound_player.c"),
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
            self.assertEqual(run.stdout.strip(), expected)

    def test_real_component_with_host_shims(self):
        self.compile_and_run(SHIM, HARNESS, "sound-player-ok")

    def test_empty_bank_is_a_valid_no_audio_project(self):
        self.assertNotEqual(EMPTY_SHIM, SHIM, "empty-bank fixture replacement must apply")
        self.compile_and_run(EMPTY_SHIM, EMPTY_HARNESS, "empty-sound-bank-ok")

    def test_malformed_bank_fails_before_audio_start(self):
        self.assertNotEqual(TRAILING_SHIM, EMPTY_SHIM, "trailing-byte fixture replacement must apply")
        self.compile_and_run(TRAILING_SHIM, INVALID_HARNESS, "invalid-sound-bank-rejected")


if __name__ == "__main__":
    unittest.main()
