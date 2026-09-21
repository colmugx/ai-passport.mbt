# The FoloToy Host is one ESP-IDF component. Everything registered here is
# ai-passport-owned glue, generated application C, the MoonBit runtime from
# the local MoonBit installation, or an explicitly selected source from the
# verified external BSP checkout.
set(HOST_ROOT "${CMAKE_CURRENT_LIST_DIR}/..")

if(NOT EXISTS "${HOST_ROOT}/upstream.cmake")
    message(FATAL_ERROR "FOTOLOY_BSP_ROOT is unset; run passport build --host folotoy-ai-passport")
endif()
include("${HOST_ROOT}/upstream.cmake")
if(NOT DEFINED FOTOLOY_BSP_ROOT OR NOT EXISTS "${FOTOLOY_BSP_ROOT}/src/bsp_display.c")
    message(FATAL_ERROR "FOTOLOY_BSP_ROOT does not point at a FoloToy BSP checkout: ${FOTOLOY_BSP_ROOT}")
endif()

if(NOT DEFINED ENV{MOON_HOME})
    message(FATAL_ERROR "MOON_HOME must point to a MoonBit installation")
endif()
set(MOON_RUNTIME "$ENV{MOON_HOME}/lib/runtime")

set(CAPTURE_DIR "${CMAKE_CURRENT_LIST_DIR}/generated/moonbit")
set(CAPTURE_MANIFEST "${CAPTURE_DIR}/sources.txt")
if(NOT EXISTS "${CAPTURE_MANIFEST}")
    message(FATAL_ERROR "MoonBit C capture manifest missing: ${CAPTURE_MANIFEST}; run passport build --host folotoy-ai-passport")
endif()
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CAPTURE_MANIFEST}")
file(STRINGS "${CAPTURE_MANIFEST}" CAPTURED_RELATIVE_SOURCES)
if(NOT CAPTURED_RELATIVE_SOURCES)
    message(FATAL_ERROR "MoonBit C capture manifest is empty")
endif()
foreach(RELATIVE_SOURCE IN LISTS CAPTURED_RELATIVE_SOURCES)
    set(SOURCE_PATH "${CAPTURE_DIR}/${RELATIVE_SOURCE}")
    if(NOT EXISTS "${SOURCE_PATH}")
        message(FATAL_ERROR "Captured MoonBit C source missing: ${SOURCE_PATH}")
    endif()
    list(APPEND CAPTURED_SOURCES "${SOURCE_PATH}")
endforeach()

set(SOUND_BANK_FILE "${HOST_ROOT}/sounds.bank")
if(NOT EXISTS "${SOUND_BANK_FILE}")
    message(FATAL_ERROR "passport device workspace is missing sounds.bank")
endif()
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${SOUND_BANK_FILE}")

# Upstream's component would also register bsp_display_lvgl.c and pull LVGL
# into the firmware. Select only the five hardware transports this Host uses.
idf_component_register(
    SRCS
        "app_main.c"
        "battery_bridge.c"
        "button_bridge.c"
        "clock_bridge.c"
        "display_bridge.c"
        "microphone_bridge.c"
        "power_bridge.c"
        "sound_player.c"
        ${CAPTURED_SOURCES}
        "${MOON_RUNTIME}/runtime.c"
        "${MOON_RUNTIME}/backtrace.c"
        "${MOON_RUNTIME}/env.c"
        "${MOON_RUNTIME}/sync_io.c"
        "${MOON_RUNTIME}/utf.c"
        "${FOTOLOY_BSP_ROOT}/src/bsp_display.c"
        "${FOTOLOY_BSP_ROOT}/src/bsp_i2c.c"
        "${FOTOLOY_BSP_ROOT}/src/bsp_battery.c"
        "${FOTOLOY_BSP_ROOT}/src/bsp_audio.c"
        "${FOTOLOY_BSP_ROOT}/src/bsp_button.c"
    INCLUDE_DIRS
        "."
        "$ENV{MOON_HOME}/include"
        "${FOTOLOY_BSP_ROOT}/include"
    REQUIRES
        log
        freertos
        esp_timer
        heap
        esp_lcd
        esp_driver_spi
        esp_driver_ledc
        esp_driver_i2c
        esp_driver_i2s
        esp_codec_dev
        button
        esp_adc
)

target_add_binary_data(${COMPONENT_LIB} "${SOUND_BANK_FILE}" BINARY RENAME_TO sounds_bank)

# Current moonc emits flat static array initializers and one mixed &&/||
# expression. Scope the exceptions to captured MoonBit C so Host and BSP
# sources retain ESP-IDF's complete warning policy.
set_source_files_properties(${CAPTURED_SOURCES} PROPERTIES
    COMPILE_OPTIONS "-Wno-missing-braces;-Wno-error=parentheses")
