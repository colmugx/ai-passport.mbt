# Build orchestration for the external FoloToy AI Passport BSP checkout
# (MIT; pinned upstream revision and provenance in the host README.md).
# `passport build --host folotoy-ai-passport` writes upstream.cmake next to
# this file, setting FOTOLOY_BSP_ROOT to the resolved checkout (project
# submodule or CLI-managed clone); the upstream sources are compiled in
# place and never copied into this tree.
if(NOT EXISTS "${CMAKE_CURRENT_LIST_DIR}/upstream.cmake")
    message(FATAL_ERROR "FOTOLOY_BSP_ROOT is unset; run passport build --host folotoy-ai-passport")
endif()
include("${CMAKE_CURRENT_LIST_DIR}/upstream.cmake")
if(NOT DEFINED FOTOLOY_BSP_ROOT OR NOT EXISTS "${FOTOLOY_BSP_ROOT}/src/bsp_display.c")
    message(FATAL_ERROR "FOTOLOY_BSP_ROOT does not point at a FoloToy BSP checkout: ${FOTOLOY_BSP_ROOT}")
endif()
#
# Upstream's own components/bsp/CMakeLists.txt also registers
# bsp_display_lvgl.c and REQUIRES esp_lvgl_port, which would drag all of
# LVGL into this firmware through whole-archive component linking. This
# host has no UI framework and spends its flash budget on the music PCM,
# so only the display, shared-I2C, battery, audio and button sources are
# selected here; the selection list is the single place to audit what enters
# the firmware. bsp_button.c additionally needs the managed espressif/button
# component and esp_adc (see idf_component.yml).
idf_component_register(
    SRCS "${FOTOLOY_BSP_ROOT}/src/bsp_display.c"
         "${FOTOLOY_BSP_ROOT}/src/bsp_i2c.c"
         "${FOTOLOY_BSP_ROOT}/src/bsp_battery.c"
         "${FOTOLOY_BSP_ROOT}/src/bsp_audio.c"
         "${FOTOLOY_BSP_ROOT}/src/bsp_button.c"
    INCLUDE_DIRS "${FOTOLOY_BSP_ROOT}/include"
    REQUIRES esp_driver_spi esp_driver_ledc esp_lcd esp_driver_i2c esp_driver_i2s esp_codec_dev button esp_adc
)
