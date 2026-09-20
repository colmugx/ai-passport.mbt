# Web Host integration tests

`run-tests.mjs` is the Web Host and CLI integration gate. It requires both
debug and release Wasm fixtures:

```sh
moon build --target wasm --release
moon build --target wasm
node hosts/web/test/run-tests.mjs
```

The suites verify:

- old single-PCM imports are absent from built Wasm;
- framebuffer, semantic input, battery, and master output behavior;
- strict APSB v1 parsing and observable failures;
- overlapping instances of one Sound, mixing, slot exhaustion, pause/resume,
  stop, one-shot retirement, and per-playback position;
- the MoonBit Sound API reaching the JavaScript runtime;
- deterministic CLI Web/device workspaces, ordinary assets, Sound bindings,
  sound banks, stale-output cleanup, and doctor behavior;
- a real Chromium AudioWorklet run with simultaneous loop and one-shot Sound
  playback, plus the downstream Web fixture boot.

`minimal-wasm.mjs` produces an application-neutral Wasm fixture for direct
Host tests. `cli-fixture-suites.mjs` builds temporary downstream projects;
generated files never become checked-in fixture sources. `browser-common.mjs`
contains the shared static server and Playwright launch path.

`--skip-browser` exists for fast local diagnosis. It is not an acceptable CI
or release gate because it does not prove browser module loading,
AudioWorklet transport, or the emitted bundle over HTTP.
