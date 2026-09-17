# The device embeds the ONE canonical normalized PCM artifact byte-for-byte
# when the project declares one (at most one pcmLoop asset): the passport CLI
# materializes it as passport_music.pcm at the workspace root once per build,
# and this component embeds that exact file. A project with no audio asset
# builds firmware that brings up the audio output but embeds no music and
# reports playback unavailable. There is no device-side conversion and no
# placeholder blob.
# Anchor on this list file's own directory: ESP-IDF's early requirement scan
# include()s component lists with CMAKE_CURRENT_SOURCE_DIR left at the
# project dir, so counting relative anchors from there is wrong.
set(MUSIC_PCM_FILE "${CMAKE_CURRENT_LIST_DIR}/../../passport_music.pcm")
set(PASSPORT_HAS_MUSIC_ASSET 0)
if(EXISTS "${MUSIC_PCM_FILE}")
    set(PASSPORT_HAS_MUSIC_ASSET 1)
endif()
# Re-configure when the blob appears, disappears, or changes.
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${MUSIC_PCM_FILE}")
idf_component_register(SRCS "music_stream.c"
    INCLUDE_DIRS "include"
    REQUIRES folotoy_bsp log freertos)
if(PASSPORT_HAS_MUSIC_ASSET)
    # The PCM lives in flash via ELF embedding, never in a heap copy. RENAME_TO
    # pins the linker symbols (_binary_passport_music_pcm_start/_end) regardless
    # of where the source file sits.
    target_add_binary_data(${COMPONENT_LIB} "${MUSIC_PCM_FILE}" BINARY RENAME_TO passport_music_pcm)
endif()
target_compile_definitions(${COMPONENT_LIB} PRIVATE
    PASSPORT_HAS_MUSIC_ASSET=${PASSPORT_HAS_MUSIC_ASSET})
