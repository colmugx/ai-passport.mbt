# The CLI always materializes the deterministic APSB bank, including the
# 16-byte empty-bank form for projects with no sounds. Embed the exact bytes in
# flash; the player validates and reads them in place without copying payloads.
set(SOUND_BANK_FILE "${CMAKE_CURRENT_LIST_DIR}/../../sounds.bank")
if(NOT EXISTS "${SOUND_BANK_FILE}")
    message(FATAL_ERROR "passport device workspace is missing sounds.bank")
endif()
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${SOUND_BANK_FILE}")

idf_component_register(SRCS "sound_player.c"
    INCLUDE_DIRS "include"
    REQUIRES folotoy_bsp log freertos)
target_add_binary_data(${COMPONENT_LIB} "${SOUND_BANK_FILE}" BINARY RENAME_TO sounds_bank)
