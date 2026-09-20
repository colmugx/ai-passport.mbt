idf_component_register(SRCS "app_main.c" REQUIRES
    log moonbit_device display_bridge battery_bridge sound_player button_bridge clock_bridge folotoy_bsp)
