# The device embeds the ONE canonical normalized PCM artifact byte-for-byte;
# the web bundle serves the same file. There is no device-side conversion:
# the passport CLI materializes the contract's pcmLoop asset as
# passport_music.pcm at the workspace root once per build, and this
# component embeds that exact file.
# Anchor on this list file's own directory: ESP-IDF's early requirement scan
# include()s component lists with CMAKE_CURRENT_SOURCE_DIR left at the
# project dir, so counting relative anchors from there is wrong.
set(MUSIC_PCM_FILE "${CMAKE_CURRENT_LIST_DIR}/../../passport_music.pcm")
if(NOT EXISTS "${MUSIC_PCM_FILE}")
    message(FATAL_ERROR "Device music PCM missing: ${MUSIC_PCM_FILE}; run passport build --host folotoy-ai-passport")
endif()
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${MUSIC_PCM_FILE}")
idf_component_register(SRCS "music_stream.c"
    INCLUDE_DIRS "include"
    REQUIRES folotoy_bsp log freertos)
# The PCM lives in flash via ELF embedding, never in a heap copy. RENAME_TO
# pins the linker symbols (_binary_passport_music_pcm_start/_end) regardless
# of where the source file sits.
target_add_binary_data(${COMPONENT_LIB} "${MUSIC_PCM_FILE}" BINARY RENAME_TO passport_music_pcm)
