# Web Host

This directory is the SDK-owned browser adapter copied byte-for-byte into each
Web build. It runs a compiled MoonBit application and the shared APSB sound
bank; it is not an application template or an audio middleware API.

## Bundle contract

The Host expects sibling files `app.wasm`, `sounds.bank`, `passport-host.js`,
`sound-worklet.js`, and `index.html`. `passport build --host web` assembles them
under `<project>/.passport/web/` together with declared ordinary assets.

Serve that directory over HTTP and open `/index.html`. Sound configuration is
part of `sounds.bank`, not the URL. Supported query parameters are:

- `battery=0..100` or `battery=none`
- `scale=<positive integer>` (the reference/dev page defaults to `3`; pass another value to override)

## Programmatic use

`createHost(options)` accepts URLs by default and injectable bytes for tests:

```js
const host = await createHost({
  wasmUrl: new URL("./app.wasm", import.meta.url),
  soundBankUrl: new URL("./sounds.bank", import.meta.url),
  canvas: document.querySelector("canvas"),
});
```

Important options are `wasmBytes`/`wasmUrl`,
`soundBankBytes`/`soundBankUrl`, `canvas`, `audioContextFactory`, `workletUrl`,
`batteryPercent`, `volume`, `muted`, `normalizeAudio`, `scale`, and internal import overrides.
Supplying Wasm bytes without a bank is an audio-less test convenience and uses
a valid empty bank; normal bundles always fetch `sounds.bank`.

The returned Host exposes lifecycle and diagnostics needed by tests and
embedding code: `tick`, `start`, `stop`, `dispose`, queued semantic input,
framebuffer access, frame count, master volume/mute, audio transport facts, and
the current list of sound playbacks. Sound controls themselves enter through
the internal Wasm imports described in `docs/WEB_HOST.md`.

## Audio implementation

`passport-host.js` parses APSB v1 and owns at most eight live playback slots.
`sound-worklet.js` receives the bank and handle commands, mixes active PCM16
sources, clamps output, and reports per-handle position. Playing one Sound more
than once creates independent handles. A ScriptProcessor implementation is the
fallback for engines without AudioWorklet support. The public MoonBit surface
remains `Sound`, `Playback`, `play`, `pause`, `resume`, `stop`, and `position`;
the browser mixer is an implementation detail.

The Host deliberately provides no codecs, media decoding, resampling,
synthesis, sequencer, exposed mixer graph, bus, effect, or plugin API.

The bundled reference/dev page is a listening aid rather than a mastering surface:
it peak-normalizes the loaded APSB bank once, keeps browser playback at unity gain,
and leaves final listening level to the browser/operating-system device volume.
Programmatic `createHost()` calls do not normalize PCM unless `normalizeAudio: true`
is requested, so embedding behavior stays explicit.

## Tests

Build the Wasm fixtures first, then run:

```sh
node hosts/web/test/run-tests.mjs
```

Use `--skip-browser` only for a local diagnostic pass. CI and release review
run the real-browser suite.
