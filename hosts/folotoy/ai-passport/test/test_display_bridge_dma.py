"""Host test for the ESP32 display bridge's double-buffered DMA pipeline.

Compiles the real display_bridge.c against small ESP-IDF/FreeRTOS shims and
models asynchronous LCD completion deterministically. The shim snapshots each
submitted DMA buffer and compares it again when completion is delivered, so a
buffer reuse bug is detected even though no real SPI peripheral is present.
"""

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HOST_ROOT = Path(__file__).resolve().parent.parent
COMPONENT = HOST_ROOT / "main"

SHIM_HEADERS = {
    "esp_err.h": r"""
#pragma once
#include <stdint.h>
typedef int esp_err_t;
#define ESP_OK 0
#define ESP_ERR_NO_MEM 0x101
#define ESP_ERR_INVALID_STATE 0x103
const char *esp_err_to_name(esp_err_t err);
#define ESP_ERROR_CHECK(expr) do { if ((expr) != ESP_OK) __builtin_abort(); } while (0)
""",
    "esp_log.h": r"""
#pragma once
#define ESP_LOGE(tag, ...) do { (void)(tag); } while (0)
#define ESP_LOGI(tag, ...) do { (void)(tag); } while (0)
""",
    "esp_heap_caps.h": r"""
#pragma once
#include <stddef.h>
#define MALLOC_CAP_DMA 1
#define MALLOC_CAP_INTERNAL 2
void *heap_caps_malloc(size_t size, unsigned caps);
void heap_caps_free(void *ptr);
""",
    "esp_timer.h": r"""
#pragma once
#include <stdint.h>
int64_t esp_timer_get_time(void);
""",
    "bsp_pins.h": r"""
#pragma once
#define BSP_LCD_W 240
#define BSP_LCD_H 320
""",
    "bsp_display.h": r"""
#pragma once
#include "esp_err.h"
typedef void *esp_lcd_panel_handle_t;
typedef void *esp_lcd_panel_io_handle_t;
esp_err_t bsp_display_init(void);
esp_lcd_panel_handle_t bsp_display_panel(void);
esp_lcd_panel_io_handle_t bsp_display_io(void);
void bsp_display_backlight(uint8_t percent);
""",
    "esp_lcd_panel_io.h": r"""
#pragma once
#include <stdbool.h>
#include "esp_err.h"
typedef void *esp_lcd_panel_io_handle_t;
typedef struct {} esp_lcd_panel_io_event_data_t;
typedef bool (*esp_lcd_panel_io_color_trans_done_cb_t)(
    esp_lcd_panel_io_handle_t,
    esp_lcd_panel_io_event_data_t *,
    void *);
typedef struct {
    esp_lcd_panel_io_color_trans_done_cb_t on_color_trans_done;
} esp_lcd_panel_io_callbacks_t;
esp_err_t esp_lcd_panel_io_register_event_callbacks(
    esp_lcd_panel_io_handle_t io,
    const esp_lcd_panel_io_callbacks_t *callbacks,
    void *user_context);
""",
    "esp_lcd_panel_ops.h": r"""
#pragma once
#include "esp_err.h"
typedef void *esp_lcd_panel_handle_t;
esp_err_t esp_lcd_panel_draw_bitmap(
    esp_lcd_panel_handle_t panel,
    int x_start, int y_start, int x_end, int y_end,
    const void *color_data);
""",
    "moonbit.h": r"""
#pragma once
#define Moonbit_array_length(array) (240)
""",
    "freertos/FreeRTOS.h": r"""
#pragma once
#include <stdint.h>
#define pdTRUE 1
#define pdFALSE 0
typedef int BaseType_t;
typedef uint32_t TickType_t;
#define pdMS_TO_TICKS(ms) ((TickType_t)(ms))
""",
    "freertos/semphr.h": r"""
#pragma once
#include "FreeRTOS.h"
typedef struct fake_sem *SemaphoreHandle_t;
SemaphoreHandle_t xSemaphoreCreateCounting(unsigned max_count, unsigned initial_count);
BaseType_t xSemaphoreGiveFromISR(SemaphoreHandle_t sem, BaseType_t *should_yield);
BaseType_t xSemaphoreTake(SemaphoreHandle_t sem, TickType_t ticks);
void vSemaphoreDelete(SemaphoreHandle_t sem);
""",
}

SHIM_SOURCE = r"""
#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "bsp_display.h"
#include "esp_heap_caps.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_timer.h"
#include "freertos/semphr.h"

#define STRIP_BYTES (240 * 20 * 2)
#define MAX_TX 16

struct fake_sem { unsigned max_count; unsigned count; };

typedef struct {
    int y0;
    int y1;
    const uint8_t *buffer;
    uint8_t snapshot[STRIP_BYTES];
} tx_t;

tx_t shim_tx[MAX_TX];
int shim_tx_count;
int shim_completion_head;
int shim_outstanding;
int shim_max_outstanding;
int shim_force_timeout;
int shim_heap_allocs;
int shim_display_init_calls;
int shim_backlight_calls;
int shim_last_backlight = -1;
void *shim_unique_buffers[2];
int shim_unique_buffer_count;

static esp_lcd_panel_io_color_trans_done_cb_t s_callback;
static void *s_callback_user;
static int64_t s_now_us;

const char *esp_err_to_name(esp_err_t err) { (void)err; return "shim"; }

void *heap_caps_malloc(size_t size, unsigned caps) {
    assert(caps == (MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL));
    assert(size == STRIP_BYTES);
    void *p = malloc(size);
    if (p != NULL) shim_heap_allocs++;
    return p;
}
void heap_caps_free(void *ptr) { if (ptr != NULL) { shim_heap_allocs--; free(ptr); } }

int64_t esp_timer_get_time(void) { s_now_us += 100; return s_now_us; }

esp_err_t bsp_display_init(void) {
    ++shim_display_init_calls;
    return ESP_OK;
}
esp_lcd_panel_handle_t bsp_display_panel(void) { return (void *)0x1; }
esp_lcd_panel_io_handle_t bsp_display_io(void) { return (void *)0x2; }
void bsp_display_backlight(uint8_t percent) {
    ++shim_backlight_calls;
    shim_last_backlight = percent;
}

esp_err_t esp_lcd_panel_io_register_event_callbacks(
    esp_lcd_panel_io_handle_t io,
    const esp_lcd_panel_io_callbacks_t *callbacks,
    void *user_context) {
    assert(io == (void *)0x2);
    s_callback = callbacks->on_color_trans_done;
    s_callback_user = user_context;
    return ESP_OK;
}

static void remember_buffer(const void *buffer) {
    for (int i = 0; i < shim_unique_buffer_count; ++i) {
        if (shim_unique_buffers[i] == buffer) return;
    }
    assert(shim_unique_buffer_count < 2);
    shim_unique_buffers[shim_unique_buffer_count++] = (void *)buffer;
}

esp_err_t esp_lcd_panel_draw_bitmap(
    esp_lcd_panel_handle_t panel,
    int x_start, int y_start, int x_end, int y_end,
    const void *color_data) {
    assert(panel == (void *)0x1);
    assert(x_start == 0 && x_end == 240);
    assert(shim_tx_count < MAX_TX);
    assert(y_end - y_start == 20);
    tx_t *tx = &shim_tx[shim_tx_count++];
    tx->y0 = y_start;
    tx->y1 = y_end;
    tx->buffer = color_data;
    memcpy(tx->snapshot, color_data, STRIP_BYTES);
    remember_buffer(color_data);
    shim_outstanding++;
    if (shim_outstanding > shim_max_outstanding) {
        shim_max_outstanding = shim_outstanding;
    }
    return ESP_OK;
}

static void complete_oldest(void) {
    assert(shim_completion_head < shim_tx_count);
    tx_t *tx = &shim_tx[shim_completion_head++];
    // DMA still owns this memory until this point. Any premature reuse makes
    // the live buffer differ from the submission snapshot.
    assert(memcmp(tx->buffer, tx->snapshot, STRIP_BYTES) == 0);
    assert(s_callback != NULL);
    esp_lcd_panel_io_event_data_t event = {};
    s_callback((void *)0x2, &event, s_callback_user);
    shim_outstanding--;
}

SemaphoreHandle_t xSemaphoreCreateCounting(unsigned max_count, unsigned initial_count) {
    struct fake_sem *sem = malloc(sizeof(*sem));
    if (sem == NULL) return NULL;
    sem->max_count = max_count;
    sem->count = initial_count;
    return sem;
}
BaseType_t xSemaphoreGiveFromISR(SemaphoreHandle_t sem, BaseType_t *should_yield) {
    assert(sem->count < sem->max_count);
    sem->count++;
    if (should_yield != NULL) *should_yield = pdFALSE;
    return pdTRUE;
}
BaseType_t xSemaphoreTake(SemaphoreHandle_t sem, TickType_t ticks) {
    assert(ticks == 1000);
    if (sem->count == 0) {
        if (shim_force_timeout) return pdFALSE;
        complete_oldest();
    }
    assert(sem->count > 0);
    sem->count--;
    return pdTRUE;
}
void vSemaphoreDelete(SemaphoreHandle_t sem) { free(sem); }
"""

HARNESS = r"""
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "display_bridge.h"

typedef struct {
    int y0;
    int y1;
    const uint8_t *buffer;
    uint8_t snapshot[240 * 20 * 2];
} tx_t;
extern tx_t shim_tx[16];
extern int shim_tx_count;
extern int shim_completion_head;
extern int shim_outstanding;
extern int shim_max_outstanding;
extern int shim_force_timeout;
extern int shim_heap_allocs;
extern int shim_display_init_calls;
extern int shim_backlight_calls;
extern int shim_last_backlight;
extern int shim_unique_buffer_count;

void ai_passport_display_begin(void);
void ai_passport_display_row(int32_t y, int32_t *rgb565);
void ai_passport_display_end(void);

static uint16_t swap16(uint16_t value) {
    return (uint16_t)((value << 8) | (value >> 8));
}

static void feed_frame(int stop_before_end) {
    int32_t row[240];
    ai_passport_display_begin();
    for (int y = 0; y < 320; ++y) {
        for (int x = 0; x < 240; ++x) {
            row[x] = (int32_t)(((y & 31) << 11) | ((x & 63) << 5) | (x & 31));
        }
        ai_passport_display_row(y, row);
        if (stop_before_end && y == 318) return;
    }
    ai_passport_display_end();
}

static void verify_success(void) {
    // Logical backlight state exists before the physical display is ready.
    assert(ai_passport_display_backlight_level() == 60);
    ai_passport_display_set_backlight(35);
    assert(ai_passport_display_backlight_level() == 35);
    assert(shim_display_init_calls == 0);
    assert(shim_backlight_calls == 0);
    assert(shim_heap_allocs == 0);

    // App construction precedes physical display init. Once panel init starts,
    // both DMA strips are essential display resources and must be reserved
    // immediately, before optional first-frame transports such as audio.
    assert(ai_passport_display_init() == 0);
    assert(shim_display_init_calls == 1);
    assert(shim_backlight_calls == 1);
    assert(shim_last_backlight == 35);
    assert(shim_heap_allocs == 2);

    // First present performs no heap allocation.
    feed_frame(0);
    assert(shim_heap_allocs == 2);
    assert(shim_tx_count == 16);
    assert(shim_completion_head == 16);
    assert(shim_outstanding == 0);
    assert(shim_max_outstanding == 2);
    assert(shim_unique_buffer_count == 2);
    for (int i = 0; i < 16; ++i) {
        assert(shim_tx[i].y0 == i * 20);
        assert(shim_tx[i].y1 == (i + 1) * 20);
    }
    // Double buffering alternates A/B and never aliases consecutive strips.
    for (int i = 2; i < 16; ++i) {
        assert(shim_tx[i].buffer == shim_tx[i - 2].buffer);
        assert(shim_tx[i].buffer != shim_tx[i - 1].buffer);
    }
    // Logical pixels are byte-swapped and presented at native resolution.
    const uint16_t *first = (const uint16_t *)shim_tx[0].snapshot;
    assert(first[0] == swap16(0x0000));
    assert(first[1] == swap16(0x0021));
    assert(first[2] == swap16(0x0042));
    assert(first[240] == swap16(0x0800));
    assert(ai_passport_display_last_present_us() > 0);
    puts("ok");
}

int main(int argc, char **argv) {
    if (argc == 1 || strcmp(argv[1], "ok") == 0) {
        verify_success();
        return 0;
    }
    assert(ai_passport_display_init() == 0);
    int32_t row[240] = {0};
    if (strcmp(argv[1], "bad-row") == 0) {
        ai_passport_display_begin();
        ai_passport_display_row(1, row);
        return 0;
    }
    if (strcmp(argv[1], "incomplete") == 0) {
        ai_passport_display_begin();
        ai_passport_display_row(0, row);
        ai_passport_display_end();
        return 0;
    }
    if (strcmp(argv[1], "timeout") == 0) {
        shim_force_timeout = 1;
        feed_frame(0);
        return 0;
    }
    return 2;
}
"""


class DisplayBridgeDmaTests(unittest.TestCase):
    def setUp(self):
        if shutil.which("cc") is None:
            self.skipTest("host C compiler is not installed")

    def _build(self, root: Path) -> Path:
        shim = root / "shim"
        for relative, content in SHIM_HEADERS.items():
            path = shim / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        (shim / "shim.c").write_text(SHIM_SOURCE)
        harness = root / "harness.c"
        harness.write_text(HARNESS)
        binary = root / "test"
        result = subprocess.run(
            [
                "cc", "-std=c11", "-Wall", "-Werror",
                "-I", str(shim),
                "-I", str(COMPONENT),
                str(shim / "shim.c"),
                str(COMPONENT / "display_bridge.c"),
                str(harness),
                "-o", str(binary),
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr or "compile failed")
        return binary

    def test_double_buffered_pipeline_and_pixels(self):
        with tempfile.TemporaryDirectory() as temporary:
            binary = self._build(Path(temporary))
            result = subprocess.run([str(binary), "ok"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            self.assertIn("ok", result.stdout)

    def test_invalid_row_incomplete_frame_and_timeout_abort(self):
        with tempfile.TemporaryDirectory() as temporary:
            binary = self._build(Path(temporary))
            for mode in ("bad-row", "incomplete", "timeout"):
                result = subprocess.run([str(binary), mode], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0, mode)


if __name__ == "__main__":
    unittest.main()
