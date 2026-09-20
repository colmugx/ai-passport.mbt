#include "display_bridge.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "bsp_display.h"
#include "bsp_pins.h"
#include "esp_heap_caps.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "moonbit.h"

#define LOGICAL_W 120
#define LOGICAL_H 160
#define SCALE 2
#define DMA_BUFFER_COUNT 2
#define PHYSICAL_STRIP_ROWS 40
#define LOGICAL_STRIP_ROWS (PHYSICAL_STRIP_ROWS / SCALE)
#define STRIP_BYTES (BSP_LCD_W * PHYSICAL_STRIP_ROWS * sizeof(uint16_t))
#define DMA_WAIT_TIMEOUT_MS 1000

_Static_assert(BSP_LCD_W == LOGICAL_W * SCALE, "LCD width must be 2x logical width");
_Static_assert(BSP_LCD_H == LOGICAL_H * SCALE, "LCD height must be 2x logical height");
_Static_assert(PHYSICAL_STRIP_ROWS % SCALE == 0, "strip must contain complete logical rows");
_Static_assert(BSP_LCD_H % PHYSICAL_STRIP_ROWS == 0, "strip rows must divide the physical frame height");

static const char *TAG = "display_bridge";
static uint16_t *s_strips[DMA_BUFFER_COUNT];
static SemaphoreHandle_t s_transfer_done;
static esp_lcd_panel_handle_t s_panel;
static int s_next_row;
static int s_pending_rows;
static int s_fill_buffer;
static int s_outstanding_order[DMA_BUFFER_COUNT];
static int s_outstanding_head;
static int s_outstanding_count;
static bool s_buffer_busy[DMA_BUFFER_COUNT];
static bool s_presenting;
static int64_t s_present_start_us;
static int64_t s_last_present_us;
static bool s_initialized;

static bool color_transfer_done(
    esp_lcd_panel_io_handle_t io,
    esp_lcd_panel_io_event_data_t *event,
    void *user_context
) {
    (void)io;
    (void)event;
    (void)user_context;
    BaseType_t should_yield = pdFALSE;
    xSemaphoreGiveFromISR(s_transfer_done, &should_yield);
    return should_yield == pdTRUE;
}

static void release_display_resources(void) {
    if (s_transfer_done != NULL) {
        vSemaphoreDelete(s_transfer_done);
        s_transfer_done = NULL;
    }
    for (int i = 0; i < DMA_BUFFER_COUNT; ++i) {
        if (s_strips[i] != NULL) {
            heap_caps_free(s_strips[i]);
            s_strips[i] = NULL;
        }
        s_buffer_busy[i] = false;
    }
    s_outstanding_head = 0;
    s_outstanding_count = 0;
}

esp_err_t ai_passport_display_init(void) {
    if (s_initialized) {
        return ESP_OK;
    }
    esp_err_t err = bsp_display_init();
    if (err != ESP_OK) {
        return err;
    }
    s_panel = bsp_display_panel();
    esp_lcd_panel_io_handle_t io = bsp_display_io();
    if (s_panel == NULL || io == NULL) {
        ESP_LOGE(TAG, "BSP returned a null panel or IO handle");
        return ESP_ERR_INVALID_STATE;
    }
    for (int i = 0; i < DMA_BUFFER_COUNT; ++i) {
        s_strips[i] = heap_caps_malloc(
            STRIP_BYTES, MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
        if (s_strips[i] == NULL) {
            ESP_LOGE(TAG, "Cannot allocate DMA strip %d (%u bytes)", i,
                     (unsigned)STRIP_BYTES);
            release_display_resources();
            return ESP_ERR_NO_MEM;
        }
    }
    s_transfer_done = xSemaphoreCreateCounting(DMA_BUFFER_COUNT, 0);
    if (s_transfer_done == NULL) {
        ESP_LOGE(TAG, "Cannot allocate LCD transfer counting semaphore");
        release_display_resources();
        return ESP_ERR_NO_MEM;
    }
    esp_lcd_panel_io_callbacks_t callbacks = {
        .on_color_trans_done = color_transfer_done,
    };
    err = esp_lcd_panel_io_register_event_callbacks(io, &callbacks, NULL);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Cannot register LCD DMA completion callback: %s",
                 esp_err_to_name(err));
        release_display_resources();
        return err;
    }
    ESP_LOGI(TAG,
             "LCD DMA strips: %d x %dx%d RGB565, %u bytes each",
             DMA_BUFFER_COUNT, BSP_LCD_W, PHYSICAL_STRIP_ROWS,
             (unsigned)STRIP_BYTES);
    s_initialized = true;
    return ESP_OK;
}

static void wait_for_oldest_transfer(void) {
    if (s_outstanding_count <= 0) {
        return;
    }
    if (xSemaphoreTake(s_transfer_done,
                       pdMS_TO_TICKS(DMA_WAIT_TIMEOUT_MS)) != pdTRUE) {
        ESP_LOGE(TAG, "LCD DMA transfer timed out with %d outstanding",
                 s_outstanding_count);
        abort();
    }
    const int completed = s_outstanding_order[s_outstanding_head];
    s_outstanding_head = (s_outstanding_head + 1) % DMA_BUFFER_COUNT;
    --s_outstanding_count;
    if (completed < 0 || completed >= DMA_BUFFER_COUNT ||
        !s_buffer_busy[completed]) {
        ESP_LOGE(TAG, "LCD DMA completion accounting corrupt");
        abort();
    }
    s_buffer_busy[completed] = false;
}

static void ensure_buffer_available(int buffer) {
    while (s_buffer_busy[buffer]) {
        wait_for_oldest_transfer();
    }
}

static void submit_strip(void) {
    if (s_pending_rows == 0) {
        return;
    }
    const int buffer = s_fill_buffer;
    if (s_buffer_busy[buffer] || s_outstanding_count >= DMA_BUFFER_COUNT) {
        ESP_LOGE(TAG, "LCD DMA submit attempted with no free slot");
        abort();
    }
    const int y0 = (s_next_row - s_pending_rows) * SCALE;
    const int y1 = y0 + s_pending_rows * SCALE;
    ESP_ERROR_CHECK(esp_lcd_panel_draw_bitmap(
        s_panel, 0, y0, BSP_LCD_W, y1, s_strips[buffer]));
    const int tail = (s_outstanding_head + s_outstanding_count) %
                     DMA_BUFFER_COUNT;
    s_outstanding_order[tail] = buffer;
    ++s_outstanding_count;
    s_buffer_busy[buffer] = true;
    s_pending_rows = 0;

    const int next = (buffer + 1) % DMA_BUFFER_COUNT;
    ensure_buffer_available(next);
    s_fill_buffer = next;
}

void ai_passport_display_begin(void) {
    if (!s_initialized || s_panel == NULL || s_transfer_done == NULL ||
        s_strips[0] == NULL || s_strips[1] == NULL || s_presenting ||
        s_outstanding_count != 0) {
        ESP_LOGE(TAG, "Display begin called before init, during a present, or with DMA outstanding");
        abort();
    }
    s_next_row = 0;
    s_pending_rows = 0;
    s_fill_buffer = 0;
    s_outstanding_head = 0;
    s_outstanding_count = 0;
    s_buffer_busy[0] = false;
    s_buffer_busy[1] = false;
    s_presenting = true;
    s_present_start_us = esp_timer_get_time();
}

void ai_passport_display_row(int32_t y, int32_t *rgb565) {
    if (!s_presenting || y != s_next_row || rgb565 == NULL ||
        Moonbit_array_length(rgb565) != LOGICAL_W) {
        ESP_LOGE(TAG, "Invalid logical row y=%ld, expected=%d", (long)y,
                 s_next_row);
        abort();
    }
    ensure_buffer_available(s_fill_buffer);
    uint16_t *strip = s_strips[s_fill_buffer];
    uint16_t *upper = &strip[s_pending_rows * SCALE * BSP_LCD_W];
    uint16_t *lower = upper + BSP_LCD_W;
    for (int x = 0; x < LOGICAL_W; ++x) {
        // FrameView exposes the canonical RGB565 integer (0xF800 for red).
        // The ST7789 SPI protocol is big-endian per pixel, while the C3 DMA
        // buffer is little-endian, so swap adjacent bytes at this one device
        // boundary. The application and SDK stay byte-order agnostic.
        const uint16_t logical_pixel = (uint16_t)rgb565[x];
        const uint16_t pixel = (uint16_t)((logical_pixel << 8) |
                                          (logical_pixel >> 8));
        upper[x * SCALE] = pixel;
        upper[x * SCALE + 1] = pixel;
    }
    memcpy(lower, upper, BSP_LCD_W * sizeof(uint16_t));
    ++s_next_row;
    ++s_pending_rows;
    if (s_pending_rows == LOGICAL_STRIP_ROWS) {
        submit_strip();
    }
}

void ai_passport_display_end(void) {
    if (!s_presenting || s_next_row != LOGICAL_H) {
        ESP_LOGE(TAG, "Display end after %d of %d logical rows", s_next_row,
                 LOGICAL_H);
        abort();
    }
    submit_strip();
    while (s_outstanding_count > 0) {
        wait_for_oldest_transfer();
    }
    s_last_present_us = esp_timer_get_time() - s_present_start_us;
    s_presenting = false;
}

int64_t ai_passport_display_last_present_us(void) {
    return s_last_present_us;
}
