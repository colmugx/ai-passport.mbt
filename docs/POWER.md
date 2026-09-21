# Application-requested sleep

Applications call `@power.request_sleep()` for button wake or
`@power.request_timed_sleep(ms)` for button or timer wake. Both requests take
effect after the current presented frame and return `false` if one is already
pending. After execution resumes, `@power.wake_reason()` returns `Button`,
`Timer`, or `Other`; it returns `None` before the first completed sleep and
while a new request is pending.

FoloToy uses ESP32-C3 light sleep so the MoonBit application and live playback
positions survive. The Host quiesces I2S input and output, suspends the codec,
turns off the backlight, and restores the codec and previous light level on
wake. Capture stops and must be requested again by the application. The three
buttons share one ADC ladder, so the Host wakes briefly every 30 ms and reads
the ADC to detect all three voltage windows. Two consecutive active readings
are required. A timer request is measured from entry into light sleep. A
press shorter than roughly two sampling periods may be missed; physical response and
power draw need on-device measurement.

The Web Host pauses application frames and its audio context, stops capture,
and resumes on a semantic keyboard press or the requested timer. Its sleep is
a browser simulation of the portable application lifecycle, not a claim that
the browser controls the computer's hardware power state.

The FoloToy wake implementation uses the ESP-IDF light-sleep timer API because
the shared ADC resistor ladder has three key voltage windows; a digital GPIO
level alone cannot identify all keys. See the [ESP32-C3 sleep mode API](https://docs.espressif.com/projects/esp-idf/en/v5.5.3/esp32c3/api-reference/system/sleep_modes.html).
