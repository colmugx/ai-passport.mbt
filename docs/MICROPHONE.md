# Microphone input

`@audio.capture_start()` requests a mono microphone stream. Check
`@audio.capture_status()` until it is `Recording`, then call
`@audio.capture_read(buffer)` with a nonempty `FixedArray[Int]`. Samples are
signed PCM16 at 16,000 Hz. A read returns the number of samples copied in
oldest-first order; zero means no samples are ready. `capture_stop()` releases
the input and discards unread samples. `capture_dropped_samples()` exposes the
count discarded when the bounded Host queue fills, and resets on each start.

`Unavailable`, `Denied`, and `Failed` are distinct results. Web capture may
enter `Requesting` while the browser asks for permission. The Web Host requests
the microphone only when the application calls `capture_start`; it does not
send the input to the speakers. Output playback remains independent. The
FoloToy Host uses the BSP's I2S RX channel beside its I2S TX playback channel.
Its queue holds 4,096 samples; the Web queue holds 8,192. Applications should
drain the queue during updates and inspect the drop count for overload.

The SDK supplies a PCM input channel only. Encoding, speech recognition,
network transport, and audio processing belong to applications or external
services. The native test stubs report `Unavailable` because no microphone is
attached. Physical microphone capture still requires on-device validation.


On FoloToy, `capture_stop()` is non-blocking with respect to an in-flight physical RX read. The Host invalidates the current capture generation immediately so the application frame loop cannot deadlock on codec/I2S input. Power transitions use a separate bounded quiesce barrier before reconfiguring the shared audio transport.
