if(NOT DEFINED ENV{MOON_HOME})
    message(FATAL_ERROR "MOON_HOME must point to the pinned MoonBit installation")
endif()

set(MOON_RUNTIME "$ENV{MOON_HOME}/lib/runtime")
idf_component_register(
    SRCS
        "${MOON_RUNTIME}/runtime.c"
        "${MOON_RUNTIME}/backtrace.c"
        "${MOON_RUNTIME}/env.c"
        "${MOON_RUNTIME}/sync_io.c"
        "${MOON_RUNTIME}/utf.c"
    INCLUDE_DIRS "$ENV{MOON_HOME}/include"
)
