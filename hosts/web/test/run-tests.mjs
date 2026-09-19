#!/usr/bin/env node
/**
 * run-tests.mjs — the single node entry for the ai-passport SDK Wasm-host
 * integration suites (R1 Wave C / W4 / R1.2 PCM asset transport). Runs
 * everything sequentially and exits non-zero on any suite failure, printing
 * one PASS/FAIL line per suite.
 *
 *   node hosts/web/test/run-tests.mjs [--skip-browser]
 *
 * Suites:
 *   1. pcm-asset          hosts/web/assets/test.pcm == frozen square wave
 *   2. abi-golden:release fixture wasm vs the FROZEN ABI v0 + fixture contract
 *   3. abi-golden:debug   import/export surface parity of the debug artifact
 *   4. host-module: createHost under node (lifecycle, canvas blit, input)
 *   5. host-module: audio seams (pcmStats, feedNormalizedPcm, SP pull, position)
 *   6. host-module: canvas-less run and dispose
 *   7. host-module: memory-growth view invalidation
 *   8. bundle             make-bundle assembly + refusal path
 *   9-16. pcm-asset:*     node suites for the PCM ASSET transport (registered
 *                         from pcm-asset-suites.mjs): minimal no-import wasm,
 *                         strict input + non-blocking load, bounded refill,
 *                         sample-exact loop, non-loop EOF, mute/volume clock,
 *                         suspended AudioContext, producer-mode exclusivity
 *  17-25. passport CLI    structural gates, source-path containment, device
 *                         workspace pruning, fixture A/B bundle assembly,
 *                         deterministic Web rebuild, doctor, and two CLI
 *                         browser bundle proofs
 *  26. browser            exact RGB565 output reaches a real HTML canvas AND
 *                         the normalized-PCM host path runs end to end in a
 *                         real browser: wasm host_pcm_write -> decode ->
 *                         audio transport handoff -> consumption reports
 *                         (playwright if available — the CI mechanism, full
 *                         proof required — else the cached
 *                         chrome-headless-shell; --skip-browser to skip)
 *  27. browser pcm-asset  the PCM asset transport in a real browser: fetch a
 *                         normalized .pcm over http -> bounded decode chunks
 *                         -> the SAME AudioWorklet transport -> consumption
 *                         past 2 full asset loops, frames continuing while
 *                         audio runs, mute not stopping the position
 *  28. browser auto-boot  the SDK's OWN hosts/web/index.html (no probe page,
 *                         no manual createHost): serve the fixture bundle,
 *                         replace app.wasm with the minimal no-import module,
 *                         navigate to /index.html?pcm=./assets/test.pcm&pcmLoop=1
 *                         and prove the DOM auto-boot contract end to end —
 *                         no ReferenceError, globalThis.__passportHost exists,
 *                         the app starts, the PCM asset loads and loops, and
 *                         canvas frames keep running while audio plays
 *
 * Prerequisites (checked, with the exact commands printed when missing):
 *   moon build --target wasm --release    # _build/wasm/release/build/fixture/fixture.wasm
 *   moon build --target wasm              # _build/wasm/debug/build/fixture/fixture.wasm
 *   node hosts/web/tools/gen-test-pcm.mjs  # (auto-run once if the asset is missing)
 *
 * Everything here is deterministic test tooling: no application state
 * machine beyond driving the frozen fixture contract (frozen ABI v0: fb ptr
 * 4096 / fb len 38400, PCM staging ptr 42496, 266 samples/frame at 16000 Hz).
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { registerPcmAssetSuites } from "./pcm-asset-suites.mjs";
import { registerCliFixtureSuites } from "./cli-fixture-suites.mjs";
import { BROWSER_LAUNCH_FLAGS, findHeadlessShell, loadPlaywright } from "./browser-common.mjs";
import { buildMinimalPassportWasm } from "./minimal-wasm.mjs";

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

const testDir = path.dirname(fileURLToPath(import.meta.url));
const webHostDir = path.resolve(testDir, ".."); // hosts/web
const repoRoot = path.resolve(webHostDir, "..", ".."); // repository root
const RELEASE_WASM = path.join(repoRoot, "_build", "wasm", "release", "build", "fixture", "fixture.wasm");
const DEBUG_WASM = path.join(repoRoot, "_build", "wasm", "debug", "build", "fixture", "fixture.wasm");
const PCM_ASSET = path.join(webHostDir, "assets", "test.pcm");
const GEN_PCM_TOOL = path.join(webHostDir, "tools", "gen-test-pcm.mjs");
const MAKE_BUNDLE_TOOL = path.join(webHostDir, "tools", "make-bundle.mjs");
const HOST_MODULE = path.join(webHostDir, "passport-host.js");
const PROBE_PAGE = path.join(testDir, "browser-probe.html");
const PCM_ASSET_PROBE_PAGE = path.join(testDir, "pcm-asset-probe.html");
const SKIP_BROWSER =
  process.argv.includes("--skip-browser") || process.env.PASSPORT_SKIP_BROWSER === "1";

// ---------------------------------------------------------------------------
// Frozen contract constants (frozen ABI v0: fb ptr 4096, fb len 38400, PCM
// staging ptr 42496, 266 samples/frame at 16000 Hz; mirrors src/hostabi and
// hosts/web/passport-host.js — duplicated here ON PURPOSE: the tests pin the
// frozen numbers, they must not drift with the code under test).
// ---------------------------------------------------------------------------

const FB_PTR = 4096; // framebuffer byte offset
const FB_LEN = 38400; // 120 * 160 RGB565 uint16
const FB_W = 120;
const FB_H = 160;
const PCM_STAGING_PTR = 42496; // 0xA600
const SAMPLES_PER_FRAME = 266; // PCM samples pushed per passport_frame
const SAMPLE_RATE = 16000;
const BLOCK_CYCLE = [0xf800, 0x07e0, 0x001f, 0xffff]; // RGB565 red/green/blue/white on N % 4
const SEL_COLOR = 0xffe0; // full-width selection row (yellow)
const SEL_Y = (sel) => 20 + sel * 8;
const MUTE_ON = 0xffff; // muted mute-block color (white)
const MUTE_OFF = 0x07ff; // unmuted mute-block color (cyan)
const BAR_COLOR = 0x07e0; // volume bar columns 118..119, rows 0..111 at vol 70
const BAR_ROWS = 112; // 160 * 70 / 100
const FIXTURE_BATTERY = 82;
/** Frozen PCM waveform: 500 Hz square at 16000 Hz, amplitude 4000 PCM16. */
const squareWave = (n) => (((n >> 4) & 1) === 1 ? -4000 : 4000);

const PASSPORT_EXPORTS = [
  "_start",
  "passport_fb_len",
  "passport_fb_ptr",
  "passport_frame",
  "passport_frame_consume",
  "passport_frame_dirty",
  "passport_input",
];
const PASSPORT_IMPORTS = [
  "host_battery_percent",
  "host_pcm_write",
  "host_playback_pos_us",
  "host_set_muted",
  "host_set_volume",
];

// ---------------------------------------------------------------------------
// Tiny assertion helpers (per-suite failure = thrown SuiteError)
// ---------------------------------------------------------------------------

class SuiteError extends Error {}
const hex = (v) => `0x${(typeof v === "bigint" ? Number(v) : v >>> 0).toString(16)}`;

function ok(cond, msg) {
  if (!cond) throw new SuiteError(msg);
}
function eq(actual, expected, msg) {
  if (!Object.is(actual, expected)) {
    throw new SuiteError(`${msg}: expected ${String(expected)}, got ${String(actual)}`);
  }
}
function eqText(actual, expected, msg) {
  if (actual !== expected) {
    throw new SuiteError(`${msg}: expected [${expected}], got [${actual}]`);
  }
}
function throwsType(fn, ctor, msg) {
  let threw = null;
  try {
    fn();
  } catch (err) {
    threw = err;
  }
  ok(threw !== null, `${msg}: expected ${ctor.name} but nothing was thrown`);
  ok(threw instanceof ctor, `${msg}: expected ${ctor.name}, got ${threw?.constructor?.name}: ${threw}`);
}

// ---------------------------------------------------------------------------
// Fixture-wasm stub harness (ABI golden suites)
// ---------------------------------------------------------------------------

/** Stub "passport" import object that records every call and captures the
 *  PCM sample stream synchronously out of wasm memory. */
function makeStubImports(batteryValue) {
  const rec = { volume: [], muted: [], batteryCalls: 0, posCalls: 0, pcmCalls: [], pcm: [] };
  let memory = null;
  const imports = {
    passport: {
      host_battery_percent() {
        rec.batteryCalls += 1;
        return batteryValue;
      },
      host_pcm_write(ptr, samples) {
        rec.pcmCalls.push([ptr, samples]);
        const dv = new DataView(memory.buffer);
        for (let i = 0; i < samples; i++) rec.pcm.push(dv.getInt16(ptr + i * 2, true));
      },
      host_set_volume(value) {
        rec.volume.push(Number(value));
      },
      host_set_muted(value) {
        rec.muted.push(Number(value));
      },
      host_playback_pos_us() {
        rec.posCalls += 1;
        return 0x1234567n; // sentinel: host-controlled, app stores but never draws it
      },
    },
  };
  return {
    imports,
    rec,
    attach(instance) {
      memory = instance.exports.memory;
      return instance.exports;
    },
  };
}

/** Read one RGB565 framebuffer pixel (uint16 LE) at logical (x, y). */
function pxOf(exports, x, y) {
  const dv = new DataView(exports.memory.buffer);
  return dv.getUint16(FB_PTR + (y * FB_W + x) * 2, true);
}

/** Drive exactly one deterministic frame and assert the dirty/consume protocol. */
function frameOnce(exports, nowUs, label) {
  exports.passport_frame(nowUs);
  eq(exports.passport_frame_dirty(), 1, `${label}: frame must mark the framebuffer dirty`);
  exports.passport_frame_consume();
  eq(exports.passport_frame_dirty(), 0, `${label}: consume must clear the dirty flag`);
}

/** The FROZEN fixture frame: exact pixels for frame N, selection `sel`, mute
 *  flag `muted`. `opts.batteryText: false` skips the battery text check. */
function assertFrozenFrame(exports, N, sel, muted, opts = {}) {
  const label = `N=${N}`;
  const block = BLOCK_CYCLE[N % 4];
  const muteColor = muted ? MUTE_ON : MUTE_OFF;
  const selY = SEL_Y(sel);

  // 8x8 frame-counter block at (0,0)-(7,7).
  for (const [x, y] of [
    [0, 0],
    [4, 3],
    [7, 0],
    [0, 7],
    [7, 7],
  ]) {
    eq(pxOf(exports, x, y), block, `${label}: block pixel (${x},${y})`);
  }
  // Gap proof: nothing is ever drawn outside the block here.
  eq(pxOf(exports, 8, 8), 0x0000, `${label}: gap pixel (8,8)`);
  eq(pxOf(exports, 8, 0), 0x0000, `${label}: gap pixel (8,0)`);
  eq(pxOf(exports, 0, 8), 0x0000, `${label}: gap pixel (0,8)`);

  // Mute block at (112,0)-(119,7): visible portion is cols 112..117, because
  // the volume bar (drawn later) overrides cols 118..119.
  eq(pxOf(exports, 112, 0), muteColor, `${label}: mute block (112,0)`);
  eq(pxOf(exports, 112, 7), muteColor, `${label}: mute block (112,7)`);
  eq(pxOf(exports, 117, 3), muteColor, `${label}: mute block (117,3)`);

  // Volume bar: cols 118..119, rows 0..111 green, EXCEPT the active
  // selection row (full-width yellow overrides the bar at its y); rows
  // 112..159 black below the bar.
  for (let y = 0; y < BAR_ROWS; y++) {
    const expected = y === selY ? SEL_COLOR : BAR_COLOR;
    eq(pxOf(exports, 118, y), expected, `${label}: bar col 118 row ${y}`);
    eq(pxOf(exports, 119, y), expected, `${label}: bar col 119 row ${y}`);
  }
  for (let y = BAR_ROWS; y < FB_H; y++) {
    eq(pxOf(exports, 118, y), 0x0000, `${label}: below-bar col 118 row ${y}`);
  }

  // Selection row: full width 1px at y = 20 + sel*8.
  for (const x of [0, 1, 60, 118, 119]) {
    eq(pxOf(exports, x, selY), SEL_COLOR, `${label}: selection row (${x},${selY})`);
  }
  eq(pxOf(exports, 30, selY - 1), 0x0000, `${label}: row above selection is black`);
  eq(pxOf(exports, 30, selY + 1), 0x0000, `${label}: row below selection is black`);

  // Battery text region around (4,150): "82%" glyph pixels make it non-black.
  if (opts.batteryText !== false) {
    let lit = 0;
    for (let y = 145; y < FB_H; y++) {
      for (let x = 0; x < 30; x++) if (pxOf(exports, x, y) !== 0x0000) lit += 1;
    }
    ok(lit > 0, `${label}: battery text region must be non-black (found ${lit} lit pixels)`);
  }
}

// ---------------------------------------------------------------------------
// Host-module suite helpers
// ---------------------------------------------------------------------------

// Node v24 has no ImageData global; the host needs `typeof ImageData ===
// "function"` to allocate the blit target. Shim it BEFORE createHost.
if (typeof globalThis.ImageData !== "function") {
  globalThis.ImageData = class ImageData {
    constructor(width, height) {
      this.width = width;
      this.height = height;
      this.data = new Uint8ClampedArray(width * height * 4);
      this.colorSpace = "srgb";
    }
  };
}

/** Fake canvas capturing putImageData calls; surface matches exactly what
 *  passport-host.js uses: getContext("2d", ...) -> { putImageData }. */
function makeFakeCanvas() {
  const puts = [];
  let ctx2d = null;
  const canvas = {
    width: 0,
    height: 0,
    style: {},
    getContext(type) {
      if (type !== "2d") return null;
      if (!ctx2d) {
        ctx2d = {
          putImageData(img, dx, dy) {
            puts.push({ img, dx, dy });
          },
        };
      }
      return ctx2d;
    },
  };
  return { canvas, puts };
}

const hostModule = await import(pathToFileURL(HOST_MODULE)); // auto-boot is DOM-guarded: inert in node

// FNV-1a (32-bit) over a byte array; identical implementation lives in the
// browser probe page so checksums computed on both sides are comparable.
function fnv1a(bytes) {
  let h = 0x811c9dc5 | 0;
  for (let i = 0; i < bytes.length; i++) {
    h ^= bytes[i];
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0).toString(16).padStart(8, "0");
}

// ---------------------------------------------------------------------------
// Suite registry
// ---------------------------------------------------------------------------

const suites = [];
const suite = (name, fn) => suites.push({ name, fn });

// --- Suite 1: PCM asset -----------------------------------------------------

suite("pcm-asset: frozen square wave (hosts/web/assets/test.pcm)", () => {
  const buf = fs.readFileSync(PCM_ASSET);
  eq(buf.length, 8000, "test.pcm byte length (4000 samples * 2 bytes)");
  for (let n = 0; n < 4000; n++) {
    const s = buf.readInt16LE(n * 2);
    if (s !== squareWave(n)) {
      throw new SuiteError(
        `test.pcm sample ${n}: expected ${squareWave(n)}, got ${s} (asset must be the FIRST 4000 samples of the frozen square wave)`,
      );
    }
  }
});

// --- Suite 2: ABI golden, release artifact ----------------------------------

suite("abi-golden:release — frozen ABI v0 + fixture contract (stub imports)", async () => {
  const bytes = fs.readFileSync(RELEASE_WASM);

  // Export/import surfaces, read from the module itself.
  const mod = new WebAssembly.Module(bytes);
  const importNames = WebAssembly.Module.imports(mod).map((i) => `${i.module}.${i.name}`);
  eqText(
    importNames.slice().sort().join(","),
    PASSPORT_IMPORTS.map((n) => `passport.${n}`).sort().join(","),
    "import surface must be exactly the five passport.host_* on module 'passport'",
  );
  const exportDesc = WebAssembly.Module.exports(mod);
  eq(exportDesc.length, 8, "export count (six passport_* + _start + memory)");
  eqText(
    exportDesc.map((e) => e.name).sort().join(","),
    [...PASSPORT_EXPORTS, "memory"].sort().join(","),
    "export surface must be exactly memory, _start and the six passport_*",
  );

  const stub = makeStubImports(FIXTURE_BATTERY);
  const { instance } = await WebAssembly.instantiate(bytes, stub.imports);
  const ex = stub.attach(instance);

  // Framebuffer geometry: heap-start-address = 65536 puts the region at 4096.
  eq(ex.passport_fb_ptr(), FB_PTR, "passport_fb_ptr");
  eq(ex.passport_fb_len(), FB_LEN, "passport_fb_len");

  // _start: init and return. volume mirrored once, mute audible, position probed.
  eq(ex.passport_frame_dirty(), 0, "framebuffer starts clean");
  ex._start();
  eq(ex.passport_frame_dirty(), 0, "still clean after _start");
  eqText(stub.rec.volume.join(","), "70", "host_set_volume log at init");
  eqText(stub.rec.muted.join(","), "0", "host_set_muted log at init");
  ok(stub.rec.posCalls >= 1, "host_playback_pos_us must be polled from wasm at least once (init probe)");
  eq(stub.rec.batteryCalls, 0, "no battery poll during init");
  eq(stub.rec.pcmCalls.length, 0, "no PCM before the first frame");

  // Frames N=0..7 at sel=0, unmuted: exact frozen pixels + one PCM chunk each.
  for (let N = 0; N <= 7; N++) {
    const samplesBefore = stub.rec.pcm.length;
    ex.passport_frame(BigInt(N) * 16667n); // now_us never drawn
    eq(ex.passport_frame_dirty(), 1, `N=${N}: dirty after frame`);
    assertFrozenFrame(ex, N, 0, false);
    eq(stub.rec.pcmCalls.length, N + 1, `N=${N}: exactly one host_pcm_write per frame`);
    eqText(
      JSON.stringify(stub.rec.pcmCalls[N]),
      JSON.stringify([PCM_STAGING_PTR, SAMPLES_PER_FRAME]),
      `N=${N}: host_pcm_write args`,
    );
    eq(stub.rec.pcm.length - samplesBefore, SAMPLES_PER_FRAME, `N=${N}: 266 samples per frame`);
    eq(ex.passport_frame_dirty(), 1, `N=${N}: dirty persists until consume`);
    ex.passport_frame_consume();
    eq(ex.passport_frame_dirty(), 0, `N=${N}: consume clears dirty`);
  }
  eq(stub.rec.batteryCalls, 8, "battery polled exactly once per frame");

  // Selection movement: Down / Up / Up-at-floor.
  ex.passport_input(1, 1); // Down press
  frameOnce(ex, 8n * 16667n, "Down");
  assertFrozenFrame(ex, 8, 1, false);
  ex.passport_input(0, 1); // Up press
  frameOnce(ex, 9n * 16667n, "Up");
  assertFrozenFrame(ex, 9, 0, false);
  ex.passport_input(0, 1); // Up at floor: stays at 0
  frameOnce(ex, 10n * 16667n, "Up at floor");
  assertFrozenFrame(ex, 10, 0, false);

  // Cap at 9: nine Downs reach sel=9, a tenth stays.
  for (let i = 1; i <= 9; i++) {
    ex.passport_input(1, 1);
    frameOnce(ex, BigInt(10 + i) * 16667n, `Down #${i}`);
    assertFrozenFrame(ex, 10 + i, i, false);
  }
  ex.passport_input(1, 1); // Down at cap: stays at 9
  frameOnce(ex, 20n * 16667n, "Down at cap");
  assertFrozenFrame(ex, 20, 9, false);

  // Unknown button codes are ignored (e.g. 7; also -1).
  ex.passport_input(7, 1);
  ex.passport_input(7, 0);
  ex.passport_input(-1, 1);
  frameOnce(ex, 21n * 16667n, "unknown buttons");
  assertFrozenFrame(ex, 21, 9, false); // nothing moved
  eqText(stub.rec.muted.join(","), "0", "unknown buttons must not toggle mute");

  // Ok toggles mute: press+release in the same flush (keyboard-like), then
  // press-only — both delivery patterns must work.
  ex.passport_input(2, 1);
  ex.passport_input(2, 0);
  frameOnce(ex, 22n * 16667n, "Ok toggle on");
  assertFrozenFrame(ex, 22, 9, true);
  eqText(stub.rec.muted.join(","), "0,1", "mute log after first Ok toggle");
  ex.passport_input(2, 1);
  frameOnce(ex, 23n * 16667n, "Ok toggle off");
  assertFrozenFrame(ex, 23, 9, false);
  eqText(stub.rec.muted.join(","), "0,1,0", "mute log across two Ok toggles");
  eqText(stub.rec.volume.join(","), "70", "volume mirrored exactly once overall");

  // Cumulative frozen waveform across all 24 frames (>= 3 required).
  eq(stub.rec.pcm.length, 24 * SAMPLES_PER_FRAME, "cumulative sample count");
  for (let i = 0; i < stub.rec.pcm.length; i++) {
    if (stub.rec.pcm[i] !== squareWave(i)) {
      throw new SuiteError(
        `cumulative PCM mismatch at global sample ${i}: expected ${squareWave(i)}, got ${stub.rec.pcm[i]}`,
      );
    }
  }

  // Second instantiation with battery = -1 (unavailable): text region fully black.
  const stub2 = makeStubImports(-1);
  const { instance: instance2 } = await WebAssembly.instantiate(bytes, stub2.imports);
  const ex2 = stub2.attach(instance2);
  ex2._start();
  ex2.passport_frame(0n);
  let lit = 0;
  for (let y = 140; y < FB_H; y++) {
    for (let x = 0; x < 40; x++) if (pxOf(ex2, x, y) !== 0x0000) lit += 1;
  }
  eq(lit, 0, "battery=-1 must leave the battery text region fully black");
  assertFrozenFrame(ex2, 0, 0, false, { batteryText: false });
  eq(stub2.rec.batteryCalls, 1, "battery polled once for the single frame");
});

// --- Suite 3: ABI golden, debug artifact surface -----------------------------

suite("abi-golden:debug — all five passport.host_* imports + parity", async () => {
  const bytes = fs.readFileSync(DEBUG_WASM);
  const mod = new WebAssembly.Module(bytes);
  const importNames = WebAssembly.Module.imports(mod).map((i) => `${i.module}.${i.name}`);
  eqText(
    importNames.slice().sort().join(","),
    PASSPORT_IMPORTS.map((n) => `passport.${n}`).sort().join(","),
    "debug artifact must keep all five passport.host_* imports",
  );
  eqText(
    WebAssembly.Module.exports(mod)
      .map((e) => e.name)
      .sort()
      .join(","),
    [...PASSPORT_EXPORTS, "memory"].sort().join(","),
    "debug export surface",
  );

  const stub = makeStubImports(FIXTURE_BATTERY);
  const { instance } = await WebAssembly.instantiate(bytes, stub.imports);
  const ex = stub.attach(instance);
  eq(ex.passport_fb_ptr(), FB_PTR, "debug passport_fb_ptr");
  eq(ex.passport_fb_len(), FB_LEN, "debug passport_fb_len");
  ex._start();
  eqText(stub.rec.volume.join(","), "70", "debug init volume log");
  ok(stub.rec.posCalls >= 1, "debug artifact keeps host_playback_pos_us alive");
  ex.passport_frame(0n);
  assertFrozenFrame(ex, 0, 0, false);
  ex.passport_frame_consume();
  eqText(
    JSON.stringify(stub.rec.pcmCalls),
    JSON.stringify([[PCM_STAGING_PTR, SAMPLES_PER_FRAME]]),
    "debug PCM call",
  );
  for (let i = 0; i < SAMPLES_PER_FRAME; i++) {
    eq(stub.rec.pcm[i], squareWave(i), `debug PCM sample ${i}`);
  }
});

// --- Suite 4: host-module lifecycle, canvas blit, input ----------------------

suite("host-module: lifecycle, canvas blit, queued input (createHost under node)", async () => {
  const releaseBytes = fs.readFileSync(RELEASE_WASM);
  let clockN = 0;
  const fakeCtx = { currentTime: 1.0, destination: {}, state: "running" };
  const fakeGain = { gain: { value: 0 }, connect() {} };
  const { canvas, puts } = makeFakeCanvas();

  const host = await hostModule.createHost({
    wasmBytes: releaseBytes,
    canvas,
    audioContextFactory: () => {
      fakeCtx.createGain = () => fakeGain;
      return fakeCtx;
    },
    nowUs: () => BigInt(clockN) * 16667n,
    batteryPercent: FIXTURE_BATTERY,
  });

  eq(globalThis.__passportHost, undefined, "auto-boot must be DOM-guarded and inert under node");
  eq(host.frameCount, 0, "frameCount starts at 0");
  eq(host.lastNowUs, null, "lastNowUs starts null");
  eq(host.volume, 70, "fixture init host_set_volume(70) is mirrored in host state");
  eq(host.muted, false, "fixture init host_set_muted(0) is mirrored in host state");
  eq(fakeGain.gain.value, 0.7, "master gain follows the fixture volume (70/100)");
  eq(host.audio.enabled, true, "injected fake context enables audio");
  eq(host.audio.kind, "none", "fake context without worklet/SP -> audio.kind 'none'");
  eq(canvas.width, 120, "canvas backing-store width");
  eq(canvas.height, 160, "canvas backing-store height");
  eq(typeof host.exports.passport_frame, "function", "host.exports exposure");
  ok(host.memory.buffer instanceof ArrayBuffer, "host.memory exposure");

  // Drive several synthetic nowUs values.
  for (clockN = 0; clockN < 3; clockN++) {
    const r = host.tick(BigInt(clockN) * 16667n);
    ok(r !== null && r.presented === true, `tick N=${clockN} must present`);
    eq(r.frameCount, clockN + 1, `tick N=${clockN} frameCount`);
  }
  eq(host.lastNowUs, 2n * 16667n, "lastNowUs echoes the last now_us (BigInt)");
  eq(puts.length, 3, "one putImageData per presented frame");

  // RGBA conversion is correct across the ENTIRE presented frame: every pixel
  // of the captured ImageData must equal rgb565ToRgba8888(framebuffer pixel).
  const lastPut = puts[puts.length - 1];
  eq(lastPut.dx, 0, "putImageData dx");
  eq(lastPut.dy, 0, "putImageData dy");
  const fbView = host.getFramebufferView();
  eq(fbView.length, FB_LEN / 2, "framebuffer view length");
  const actualRgba = new Uint32Array(lastPut.img.data.buffer);
  for (let i = 0; i < fbView.length; i++) {
    const expected = hostModule.rgb565ToRgba8888(fbView[i]);
    if (actualRgba[i] !== expected) {
      throw new SuiteError(
        `RGBA mismatch at pixel ${i} (x=${i % FB_W}, y=${(i / FB_W) | 0}): fb=${hex(fbView[i])} ` +
          `expected rgba=${hex(expected)} got rgba=${hex(actualRgba[i])}`,
      );
    }
  }

  // Queued input reaches wasm before the next frame (pixel effect).
  host.queueInput(hostModule.BUTTON.Down, true);
  eq(host.inputQueueLength, 1, "queueInput enqueues");
  clockN = 3;
  const r = host.tick(BigInt(3) * 16667n); // N=3, sel -> 1, row y=28
  ok(r.presented, "input frame presents");
  eq(host.getFramebufferView()[28 * FB_W], SEL_COLOR, "queued Down moved the selection row to y=28");
  eq(host.getFramebufferView()[20 * FB_W], 0x0000, "previous selection row cleared");
  throwsType(() => host.queueInput(7, true), TypeError, "queueInput(7) must throw");

  // tick argument validation: strings rejected, finite numbers accepted.
  throwsType(() => host.tick("soon"), TypeError, "tick('soon') must throw");
  const rNum = host.tick(5_000_000);
  ok(rNum.presented, "tick(number) drives a frame");
  eq(host.lastNowUs, 5000000n, "tick(number) normalizes to BigInt microseconds");

  // Playback position seam (kind "none" path): report + mutating currentTime.
  // Formula (hosts/web/README.md):
  //   position_us = round((consumedSamples + max(0, now - snapshotTime) * 16000) * 1e6 / 16000)
  eq(host.playbackPosUs(), 0n, "position is 0n before any consumption report");
  host.onAudioReport({ consumed: 1000 }); // snapshot at currentTime = 1.0
  eq(host.playbackPosUs(), 62500n, "position = 1000 samples * 62.5 us at snapshot time");
  fakeCtx.currentTime = 1.5;
  eq(host.playbackPosUs(), 562500n, "position interpolates: (1000 + 0.5*16000) * 62.5 = 562500");

  // pcmStats counts the wasm import path only (5 frames driven so far:
  // 3 in the loop + the input frame + the tick(number) frame).
  eq(host.pcmStats.calls, 5, "one host_pcm_write per frame");
  eq(host.pcmStats.bytesReceived, 5 * SAMPLES_PER_FRAME * 2, "bytes received per frame chunk");
  eq(host.pcmStats.droppedSamples, 0, "nothing dropped");

  host.dispose();
});

// --- Suite 5: host-module audio seams ----------------------------------------

suite("host-module: audio seams (pcmStats, feedNormalizedPcm, SP pull, position)", async () => {
  const releaseBytes = fs.readFileSync(RELEASE_WASM);
  let sp = null;
  const fakeCtx = {
    currentTime: 0,
    destination: {},
    createGain: () => ({ gain: { value: 0 }, connect() {} }),
    createScriptProcessor: (size) => {
      sp = { bufferSize: size, onaudioprocess: null, connect() {} };
      return sp;
    },
  };
  const host = await hostModule.createHost({ wasmBytes: releaseBytes, audioContextFactory: () => fakeCtx });
  eq(host.audio.kind, "script", "ScriptProcessor fallback selected when no AudioWorklet exists");
  ok(sp !== null && typeof sp.onaudioprocess === "function", "SP node wired with onaudioprocess");

  // feedNormalizedPcm shares the decode+queue path but never touches pcmStats.
  eq(host.pcmStats.calls, 0, "stats start at zero");
  host.feedNormalizedPcm(new Int16Array([4000, -4000, 16384, -32768]));
  eq(host.pcmStats.calls, 0, "feedNormalizedPcm must not count in pcmStats.calls");
  eq(host.pcmStats.bytesReceived, 0, "feedNormalizedPcm must not count in pcmStats.bytesReceived");

  // SP pull drains the queue in order, decoded PCM16 -> Float32 (/32768).
  const out = new Float32Array(sp.bufferSize);
  sp.onaudioprocess({ outputBuffer: { getChannelData: (ch) => (ch === 0 ? out : null) } });
  eq(out[0], 4000 / 32768, "decoded sample 0");
  eq(out[1], -4000 / 32768, "decoded sample 1");
  eq(out[2], 0.5, "decoded sample 2 (16384/32768)");
  eq(out[3], -1, "decoded sample 3 (-32768/32768)");
  eq(out[4], 0, "underrun after queue drains outputs silence");
  // The pull sets the position snapshot: consumed=4 at currentTime=0.
  eq(host.playbackPosUs(), 250n, "position after pull = 4 samples * 62.5 us");
  fakeCtx.currentTime = 0.01;
  eq(host.playbackPosUs(), 10250n, "position = (4 + 0.01*16000) * 62.5 = 10250 us");

  // ArrayBuffer input path + odd-length rejection.
  host.feedNormalizedPcm(new Int16Array([1000, -1000]).buffer);
  throwsType(() => host.feedNormalizedPcm(new ArrayBuffer(3)), TypeError, "odd-length PCM buffer must throw");

  // Direct import call: writes count in pcmStats (probe bytes into the
  // staging region, which the app rewrites before every real push).
  const dv = new DataView(host.memory.buffer);
  dv.setInt16(PCM_STAGING_PTR, 4000, true);
  dv.setInt16(PCM_STAGING_PTR + 2, -4000, true);
  host.imports.passport.host_pcm_write(PCM_STAGING_PTR, 2);
  let stats = host.pcmStats;
  eq(stats.calls, 1, "import path counts calls");
  eq(stats.bytesReceived, 4, "import path counts copied-out bytes only");

  // Out-of-range import call throws RangeError but still counts as a call.
  throwsType(
    () => host.imports.passport.host_pcm_write(0xfffff0, 64),
    RangeError,
    "out-of-range host_pcm_write must throw RangeError",
  );
  stats = host.pcmStats;
  eq(stats.calls, 2, "rejected call still counted in calls");
  eq(stats.bytesReceived, 4, "rejected call copies no bytes");

  // A wasm frame pushes its own chunk through the same import.
  host.tick(0n);
  stats = host.pcmStats;
  eq(stats.calls, 3, "frame push counted");
  eq(stats.bytesReceived, 4 + SAMPLES_PER_FRAME * 2, "frame push bytes counted");
  eq(stats.droppedSamples, 0, "SP drains; nothing dropped");

  // setVolume/setMuted clamping per the host code (same path as the imports).
  eq(host.volume, 70, "fixture volume before host-side changes");
  host.setVolume(150);
  eq(host.volume, 100, "volume clamps high at 100");
  host.setVolume(-3);
  eq(host.volume, 0, "volume clamps low at 0");
  host.setVolume(Number.NaN);
  eq(host.volume, 0, "NaN volume -> 0");
  host.setVolume(55);
  eq(host.volume, 55, "in-range volume passes through");
  host.setMuted(true);
  eq(host.muted, true, "setMuted(true)");
  host.setMuted(0);
  eq(host.muted, false, "setMuted(0)");

  host.dispose();
});

// --- Suite 6: host-module canvas-less run + dispose --------------------------

suite("host-module: canvas-less run and dispose", async () => {
  const releaseBytes = fs.readFileSync(RELEASE_WASM);
  const host = await hostModule.createHost({ wasmBytes: releaseBytes, nowUs: () => 42n });
  eq(host.audio.enabled, false, "no audio factory -> audio disabled");
  eq(host.audio.kind, "none", "no audio factory -> kind none");

  const r = host.tick(42n);
  ok(r !== null && r.presented === true, "canvas-less tick still runs the dirty/consume protocol");
  eq(r.frameCount, 1, "frameCount advances canvas-less");
  eq(host.lastNowUs, 42n, "lastNowUs echoes");
  eq(host.exports.passport_frame_dirty(), 0, "consume ran even without presentation");
  eq(host.getFramebufferView()[0], BLOCK_CYCLE[0], "framebuffer reachable without canvas (N=0 red)");

  // dispose stops the loop and freezes the host.
  host.start(); // node fallback: 16 ms interval
  host.dispose();
  eq(host.tick(43n), null, "tick after dispose returns null");
  const frozen = host.frameCount;
  await new Promise((resolve) => setTimeout(resolve, 80));
  eq(host.frameCount, frozen, "interval must not tick after dispose");
  host.dispose(); // idempotent
  host.start(); // no-op after dispose
  await new Promise((resolve) => setTimeout(resolve, 80));
  eq(host.frameCount, frozen, "start after dispose is a no-op");
});

// --- Suite 7: host-module memory growth --------------------------------------

suite("host-module: memory growth re-creates framebuffer views", async () => {
  const releaseBytes = fs.readFileSync(RELEASE_WASM);
  const host = await hostModule.createHost({ wasmBytes: releaseBytes, nowUs: () => 0n });
  host.tick(0n); // N=0 red
  const view1 = host.getFramebufferView();
  const buf1 = view1.buffer;
  host.tick(0n); // N=1 green

  host.memory.grow(1); // detaches every ArrayBuffer view of the old memory
  eq(buf1.byteLength, 0, "old backing buffer must be detached after memory.grow");
  const view2 = host.getFramebufferView();
  ok(view2 !== view1, "getFramebufferView must return a fresh view after growth");
  ok(view2.buffer === host.memory.buffer, "fresh view must bind to the grown memory");
  eq(view2.length, FB_LEN / 2, "fresh view length");
  eq(view2[0], BLOCK_CYCLE[1], "framebuffer content survives growth (N=1 green)");
  const r = host.tick(0n); // N=2 blue
  ok(r !== null && r.presented, "app keeps running after growth");
  eq(view2[0], BLOCK_CYCLE[2], "post-growth frame lands in the re-created view");
  host.dispose();
});

// --- Suite 8: bundle ----------------------------------------------------------

suite("bundle: make-bundle assembly, default outdir, refusal", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "passport-bundle-test-"));
  try {
    const release = fs.readFileSync(RELEASE_WASM);
    const asset = fs.readFileSync(PCM_ASSET);

    const res = spawnSync(process.execPath, [MAKE_BUNDLE_TOOL, tmp], { encoding: "utf8" });
    eq(res.status, 0, `make-bundle into temp dir must succeed; stderr: ${res.stderr}`);
    ok(fs.readFileSync(path.join(tmp, "app.wasm")).equals(release), "bundle/app.wasm byte-equals the release fixture wasm");
    ok(
      fs.readFileSync(path.join(tmp, "assets", "test.pcm")).equals(asset),
      "bundle/assets/test.pcm byte-equals the generated asset",
    );

    // Default outdir (_build/passport-bundle, gitignored).
    const res2 = spawnSync(process.execPath, [MAKE_BUNDLE_TOOL], { encoding: "utf8" });
    eq(res2.status, 0, `make-bundle default outdir must succeed; stderr: ${res2.stderr}`);
    ok(
      fs.readFileSync(path.join(repoRoot, "_build", "passport-bundle", "app.wasm")).equals(release),
      "default bundle app.wasm byte-equals the release fixture wasm",
    );

    // Refusal path: missing wasm -> exit non-zero, message names the build command.
    const res3 = spawnSync(process.execPath, [MAKE_BUNDLE_TOOL, path.join(tmp, "refused")], {
      encoding: "utf8",
      env: { ...process.env, PASSPORT_FIXTURE_WASM: "/nonexistent/fixture.wasm" },
    });
    ok(res3.status !== 0, "missing wasm must exit non-zero");
    const text = `${res3.stdout}\n${res3.stderr}`;
    ok(text.includes("moon build"), `refusal must tell the user the moon build command; got: ${text.trim()}`);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// --- Suites 9-16: PCM asset transport (node) --------------------------------

registerPcmAssetSuites({
  suite,
  ok,
  eq,
  eqText,
  throwsType,
  SuiteError,
  hostModule,
  fs,
  releaseWasmPath: RELEASE_WASM,
});

// --- Suites 17-25: passport CLI fixtures (assembly + real browser) ----------

registerCliFixtureSuites({
  suite,
  ok,
  eq,
  eqText,
  SuiteError,
  repoRoot,
  webHostDir,
});

// --- Suite 26: browser --------------------------------------------------------

/** Node-side golden for the browser probe: an independent wasm instance
 *  drives the EXACT same frame/input sequence as hosts/web/test/
 *  browser-probe.html and derives the expected FNV-1a checksums. */
async function computeBrowserExpectation() {
  const host = await hostModule.createHost({ wasmBytes: fs.readFileSync(RELEASE_WASM) });
  for (let n = 0; n < 5; n++) host.tick(BigInt(n) * 16667n); // frames N=0..4, sel=0
  host.queueInput(hostModule.BUTTON.Down, true);
  host.tick(5n * 16667n); // frame N=5, sel=1 (row y=28)
  const fb = host.getFramebufferView();
  // Expected canvas ImageData bytes: RGBA8888 of every RGB565 pixel, in order.
  const expectedCanvas = Buffer.alloc(fb.length * 4);
  for (let i = 0; i < fb.length; i++) {
    const u = hostModule.rgb565ToRgba8888(fb[i]);
    expectedCanvas[i * 4] = u & 0xff;
    expectedCanvas[i * 4 + 1] = (u >>> 8) & 0xff;
    expectedCanvas[i * 4 + 2] = (u >>> 16) & 0xff;
    expectedCanvas[i * 4 + 3] = (u >>> 24) & 0xff;
  }
  const expectedFb = Buffer.from(fb.buffer, fb.byteOffset, fb.byteLength);
  const out = {
    frameCount: host.frameCount,
    lastNowUs: String(host.lastNowUs),
    volume: host.volume,
    canvasCrc: fnv1a(expectedCanvas),
    fbCrc: fnv1a(expectedFb),
  };
  host.dispose();
  return out;
}

function startProbeServer(bundleDir) {
  const server = http.createServer((req, res) => {
    const urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
    let filePath = null;
    if (urlPath === "/bundle/app.wasm") filePath = path.join(bundleDir, "app.wasm");
    else if (urlPath === "/passport-host.js") filePath = HOST_MODULE;
    else if (urlPath === "/pcm-worklet.js") filePath = path.join(webHostDir, "pcm-worklet.js");
    else if (urlPath === "/" || urlPath === "/test/browser-probe.html") filePath = PROBE_PAGE;
    else if (urlPath === "/test/pcm-asset-probe.html") filePath = PCM_ASSET_PROBE_PAGE;
    else if (urlPath === "/assets/test.pcm") filePath = path.join(bundleDir, "assets", "test.pcm");
    else if (urlPath === "/assets/minimal.wasm") filePath = path.join(bundleDir, "assets", "minimal.wasm");
    if (!filePath || !fs.existsSync(filePath)) {
      res.writeHead(404, { "content-type": "text/plain" });
      res.end("not found");
      return;
    }
    const type = filePath.endsWith(".wasm")
      ? "application/wasm"
      : filePath.endsWith(".html")
        ? "text/html; charset=utf-8"
        : filePath.endsWith(".js")
          ? "text/javascript"
          : filePath.endsWith(".pcm")
            ? "application/octet-stream"
            : "application/octet-stream";
    res.writeHead(200, { "content-type": type });
    res.end(fs.readFileSync(filePath));
  });
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => resolve(server));
  });
}

async function runProbeInPlaywright(url) {
  const pw = await loadPlaywright();
  if (!pw) return { path: null, mechanism: null, payload: null };
  if (!pw.chromium || typeof pw.chromium.launch !== "function") return { path: null, mechanism: null, payload: null };
  const browser = await pw.chromium.launch({ headless: true, args: BROWSER_LAUNCH_FLAGS });
  try {
    const page = await browser.newPage();
    await page.goto(url, { waitUntil: "load", timeout: 30_000 });
    await page.waitForFunction(
      () => {
        const el = document.getElementById("probe-result");
        return el !== null && el.textContent !== null && el.textContent.trimStart().startsWith("{");
      },
      null,
      { timeout: 45_000 },
    );
    return {
      path: "playwright (cached chromium)",
      mechanism: "playwright", // the CI mechanism: full audio proof REQUIRED
      payload: JSON.parse(await page.textContent("#probe-result")),
    };
  } finally {
    await browser.close().catch(() => {});
  }
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
// The self-contained data: probe is retried a bounded number of times:
// intermittent headless-shell data:-URL navigation was observed on this
// machine (no payload in ~1 of 4 runs). The http probe is NOT retried — on
// machines where browser http is dead it deterministically burns its full
// timeout, so it runs exactly once per suite invocation.
const DATA_PROBE_ATTEMPTS = 3;
const DATA_PROBE_RETRY_DELAY_MS = 1500;

/** Run chrome-headless-shell --dump-dom against a URL and extract the probe
 *  payload. Returns { path, mechanism, payload } with payload === null when
 *  the DOM has no finished probe result (page never loaded / script never
 *  completed). */
function runShellProbe(url, label, timeoutMs) {
  const bin = findHeadlessShell();
  if (!bin) return { path: null, mechanism: null, payload: null };
  const res = spawnSync(
    bin,
    [
      ...BROWSER_LAUNCH_FLAGS, // includes --autoplay-policy=no-user-gesture-required
      "--virtual-time-budget=20000",
      `--timeout=${timeoutMs}`,
      "--dump-dom",
      url,
    ],
    { encoding: "utf8", timeout: timeoutMs + 60_000, maxBuffer: 64 * 1024 * 1024 },
  );
  const m = res.stdout ? /<pre id="probe-result">([\s\S]*?)<\/pre>/.exec(res.stdout) : null;
  const text = m ? m[1].trim() : null;
  if (!text || !text.startsWith("{")) {
    return {
      path: `chrome-headless-shell (${label})`,
      mechanism: "shell",
      payload: null,
      note: text === "booting" ? "probe script did not finish" : text === null ? `page did not load (${String(res.stderr).split("\n")[0] || "no stderr"})` : text,
    };
  }
  try {
    return { path: `chrome-headless-shell (${label})`, mechanism: "shell", payload: JSON.parse(text) };
  } catch {
    return { path: `chrome-headless-shell (${label})`, mechanism: "shell", payload: null, note: `unparsable probe payload: ${text.slice(0, 200)}` };
  }
}

/** Self-contained probe fallback: this environment's chrome-headless-shell
 *  cannot complete plain http navigations ("Page load timed out" even for a
 *  static page), so instead of fetching over the throwaway server the probe
 *  page is delivered as a data: URL and receives (a) the unmodified
 *  passport-host.js source as a blob module import, (b) the worklet source as
 *  a blob URL for options.workletUrl, and (c) the bundle's app.wasm bytes
 *  inline (base64 -> ArrayBuffer -> options.wasmBytes).
 *
 * AUDIO IS REAL here too: no audioContextFactory override, so createHost
 * constructs the real AudioContext at 16000 Hz. A data: page has an opaque
 * origin and no server, so the host's default worklet location (resolved
 * against the blob module's import.meta.url) could not even be built as a
 * URL — hence the explicit blob workletUrl. If addModule refuses the blob,
 * the host's documented ScriptProcessor fallback takes over and the payload
 * records audioKind "script" plus audioWorkletError (documented degradation;
 * the http path prefers a real worklet).
 *
 * The assertion payload, the audio observers/wait and the frame/input
 * sequence are LOGICALLY IDENTICAL to hosts/web/test/browser-probe.html —
 * only the loading path differs. */
function buildSelfContainedProbeUrl(bundleDir) {
  const hostB64 = fs.readFileSync(HOST_MODULE).toString("base64");
  const workletB64 = fs.readFileSync(path.join(webHostDir, "pcm-worklet.js")).toString("base64");
  const wasmB64 = fs.readFileSync(path.join(bundleDir, "app.wasm")).toString("base64");
  const html = `<!doctype html><html><head><meta charset="utf-8"><title>passport self-contained probe</title></head>
<body><canvas id="probe-canvas" width="120" height="160"></canvas>
<pre id="probe-result">booting</pre>
<script type="module">
(async () => {
  const resultEl = document.getElementById("probe-result");
  // ---- helpers: byte-identical logic to browser-probe.html ----
  function fnv1a(bytes) {
    let h = 0x811c9dc5 | 0;
    for (let i = 0; i < bytes.length; i++) { h ^= bytes[i]; h = Math.imul(h, 0x01000193); }
    return (h >>> 0).toString(16).padStart(8, "0");
  }
  function installAudioObservers(host) {
    const obs = { kind: host.audio.kind, posted: 0, reports: 0, consumed: 0, filled: 0, underruns: 0, dropped: 0 };
    if (obs.kind === "worklet" && host.audio.node && host.audio.node.port) {
      const port = host.audio.node.port;
      const origPost = port.postMessage.bind(port);
      port.postMessage = (msg, ...rest) => {
        if (msg && msg.type === "pcm" && msg.data instanceof Float32Array) obs.posted += msg.data.length;
        return origPost(msg, ...rest);
      };
      port.addEventListener("message", (ev) => {
        const r = ev.data;
        if (!r || typeof r !== "object") return;
        obs.reports += 1;
        if (typeof r.consumed === "number") obs.consumed = Math.max(obs.consumed, r.consumed);
        if (typeof r.filled === "number") obs.filled = Math.max(obs.filled, r.filled);
        if (typeof r.underruns === "number") obs.underruns = r.underruns;
        if (typeof r.dropped === "number") obs.dropped = r.dropped;
      });
    } else if (obs.kind === "script" && host.audio.node) {
      const sp = host.audio.node;
      const origPull = sp.onaudioprocess;
      sp.onaudioprocess = (event) => {
        origPull(event);
        obs.reports += 1;
        const total = Math.round(Number(host.playbackPosUs()) / 62.5);
        if (Number.isFinite(total) && total > obs.consumed) obs.consumed = total;
        obs.filled = obs.consumed;
      };
    }
    return obs;
  }
  async function waitForAudioProof(host, obs) {
    const startedMs = Date.now();
    const startAudioTime = host.audio.ctx ? host.audio.ctx.currentTime : 0;
    await new Promise((resolve) => {
      const timer = setInterval(() => {
        host.resumeAudio();
        const audioElapsedS = host.audio.ctx ? host.audio.ctx.currentTime - startAudioTime : 0;
        if (
          obs.consumed > 0 ||
          host.audio.kind === "none" ||
          audioElapsedS >= 3.0 ||
          Date.now() - startedMs >= 10000
        ) {
          clearInterval(timer);
          resolve();
        }
      }, 50);
    });
    return Date.now() - startedMs;
  }
  // ---- probe body: identical sequence and payload to browser-probe.html ----
  try {
    const hostSrc = atob("${hostB64}");
    const workletSrc = atob("${workletB64}");
    const mod = await import(URL.createObjectURL(new Blob([hostSrc], { type: "text/javascript" })));
    const wasmBytes = Uint8Array.from(atob("${wasmB64}"), (c) => c.charCodeAt(0)).buffer;
    const canvas = document.getElementById("probe-canvas");
    let n = 0;
    // REAL audio (no audioContextFactory): createHost builds the real
    // AudioContext; the launcher passes
    // --autoplay-policy=no-user-gesture-required so it starts running.
    const host = await mod.createHost({
      canvas,
      wasmBytes,
      workletUrl: URL.createObjectURL(new Blob([workletSrc], { type: "text/javascript" })),
      nowUs: () => BigInt(n) * 16667n,
    });
    host.resumeAudio();
    const obs = installAudioObservers(host);
    for (; n < 5; n++) {
      const r = host.tick(BigInt(n) * 16667n);
      if (!r || !r.presented) throw new Error("tick not presented at N=" + n);
    }
    host.queueInput(1, true);
    n += 1;
    const last = host.tick(5n * 16667n);
    if (!last || !last.presented) throw new Error("input frame not presented");
    const img = canvas.getContext("2d").getImageData(0, 0, 120, 160);
    const canvasCrc = fnv1a(img.data);
    const fb = host.getFramebufferView();
    const fbCrc = fnv1a(new Uint8Array(fb.buffer, fb.byteOffset, fb.byteLength));
    const audioWaitMs = await waitForAudioProof(host, obs);
    const stats = host.pcmStats;
    resultEl.textContent = JSON.stringify({
      status: "ok",
      frameCount: host.frameCount,
      lastNowUs: String(host.lastNowUs),
      volume: host.volume,
      fbLen: fb.length,
      selCheck: fb[28 * 120] === 0xffe0 ? 1 : 0,
      canvasCrc,
      fbCrc,
      audioKind: host.audio.kind,
      audioReason: host.audio.reason,
      audioWorkletError: host.audio.workletError,
      pcmCalls: stats.calls,
      pcmBytes: stats.bytesReceived,
      audioFilled: host.audio.kind === "worklet" ? obs.posted : obs.filled,
      audioConsumed: obs.consumed,
      audioWaitMs,
      audioProof: obs.consumed > 0 ? "full" : "ingest-only",
    });
  } catch (err) {
    resultEl.textContent = JSON.stringify({
      status: "error",
      message: String(err && err.message ? err.message : err),
    });
  }
})();
</script></body></html>`;
  return `data:text/html;base64,${Buffer.from(html).toString("base64")}`;
}

suite("browser: exact RGB565 canvas + normalized-PCM audio in a real browser", async () => {
  if (SKIP_BROWSER) {
    console.log("  skipped by --skip-browser / PASSPORT_SKIP_BROWSER=1");
    return;
  }
  const bundleDir = fs.mkdtempSync(path.join(os.tmpdir(), "passport-browser-bundle-"));
  let server = null;
  try {
    const res = spawnSync(process.execPath, [MAKE_BUNDLE_TOOL, bundleDir], { encoding: "utf8" });
    eq(res.status, 0, `browser suite bundle assembly must succeed; stderr: ${res.stderr}`);
    const expected = await computeBrowserExpectation();

    // Path 1: playwright (cached chromium) against the http-served probe page.
    //         The CI mechanism: the FULL audio proof is REQUIRED here.
    // Path 2: chrome-headless-shell --dump-dom against the same http page.
    // Path 3: chrome-headless-shell against a self-contained data: URL probe
    //         (used when the browser cannot load http in this environment).
    // Paths 2+3 are local FALLBACKS: if the render side never reports
    // consumption they may pass ingest-only, with an explicit printed
    // degradation line — never usable by CI.
    server = await startProbeServer(bundleDir);
    const url = `http://127.0.0.1:${server.address().port}/test/browser-probe.html`;
    let outcome = { path: null, mechanism: null, payload: null, note: null };
    try {
      const pw = await runProbeInPlaywright(url);
      if (pw.payload) outcome = pw;
      else if (pw.note) console.log(`  playwright unavailable: ${pw.note}`);
    } catch (err) {
      console.log(`  playwright path failed (${err && err.message ? err.message : err}); trying chrome-headless-shell`);
    }
    if (!outcome.payload) {
      outcome = runShellProbe(url, "http probe page", 8_000); // once per run: known-dead http burns its timeout
      if (!outcome.payload) {
        console.log(`  http probe did not complete (${outcome.note || "no payload"}); trying self-contained data: probe`);
        const dataUrl = buildSelfContainedProbeUrl(bundleDir);
        const notes = [];
        for (let attempt = 1; attempt <= DATA_PROBE_ATTEMPTS && !outcome.payload; attempt++) {
          if (attempt > 1) {
            await sleep(DATA_PROBE_RETRY_DELAY_MS);
            console.log(
              `  self-contained data: probe attempt ${attempt}/${DATA_PROBE_ATTEMPTS} (intermittent headless-shell data: navigation)`,
            );
          }
          const retried = runShellProbe(dataUrl, `self-contained data: probe, attempt ${attempt}/${DATA_PROBE_ATTEMPTS}`, 20_000);
          if (retried.payload) {
            outcome = retried;
          } else {
            notes.push(retried.note || "no payload");
          }
        }
        if (!outcome.payload) outcome.note = notes.join("; ");
      }
    }
    ok(
      outcome.payload !== null,
      "no browser path produced a probe result (playwright + chrome-headless-shell both unusable)" +
        (outcome.note ? `; attempts: ${outcome.note}` : ""),
    );
    const { payload, path: usedPath } = outcome;

    // ---- gate 1: clean boot (as before) ----
    ok(payload.status === "ok", `probe must boot cleanly; payload: ${JSON.stringify(payload)}`);
    console.log(`  browser path: ${usedPath} [mechanism: ${outcome.mechanism}]`);

    // ---- gate 2: audio facts observed in the page (before display eqs, so a
    // broken payload names the audio gap first) ----
    ok(
      typeof payload.pcmCalls === "number" && payload.pcmCalls > 0 && payload.pcmBytes > 0,
      `wasm must push normalized PCM through host_pcm_write in the real browser ` +
        `(pcmCalls=${payload.pcmCalls} pcmBytes=${payload.pcmBytes})`,
    );
    ok(
      payload.audioKind === "worklet" || payload.audioKind === "script",
      `audioKind must be "worklet" or "script" in a real browser, got ${JSON.stringify(payload.audioKind)}` +
        (payload.audioReason ? ` (audioReason: ${payload.audioReason})` : ""),
    );
    ok(
      typeof payload.audioFilled === "number" && payload.audioFilled > 0,
      `decoded PCM must reach the audio transport (audioFilled=${payload.audioFilled})`,
    );
    console.log(
      `  audio proof: kind=${payload.audioKind} pcmCalls=${payload.pcmCalls} pcmBytes=${payload.pcmBytes} ` +
        `filled=${payload.audioFilled} consumed=${payload.audioConsumed} proof=${payload.audioProof} ` +
        `waitMs=${payload.audioWaitMs}` +
        (payload.audioWorkletError ? ` workletError=${payload.audioWorkletError}` : ""),
    );

    // ---- gate 3: display/input equality (UNCHANGED strength) ----
    eq(payload.frameCount, expected.frameCount, "probe frameCount (status/fps sanity: exact tick count)");
    eq(payload.lastNowUs, expected.lastNowUs, "probe lastNowUs");
    eq(payload.fbLen, FB_LEN / 2, "probe framebuffer view length");
    eq(payload.volume, expected.volume, "probe fixture volume");
    eq(payload.selCheck, 1, "queued Down moved the selection row in the browser too");
    eq(payload.fbCrc, expected.fbCrc, "browser wasm framebuffer must be deterministic and equal node's");
    eq(
      payload.canvasCrc,
      expected.canvasCrc,
      "canvas ImageData RGBA must equal host RGB565->RGBA of the same framebuffer (round-trip equality)",
    );

    // ---- gate 4: end-to-end audio consumption, mechanism-dependent ----
    if (outcome.mechanism === "playwright") {
      ok(
        typeof payload.audioConsumed === "number" && payload.audioConsumed > 0 && payload.audioProof === "full",
        `the playwright path (CI mechanism) must prove the FULL host audio path end to end: ` +
          `audioConsumed=${payload.audioConsumed} audioProof=${JSON.stringify(payload.audioProof)}`,
      );
    } else if (payload.audioProof !== "full") {
      // Local chrome-headless-shell FALLBACK ONLY (never used by CI): render
      // consumption is not observable in this environment. This pass is a
      // documented environmental degradation — the printed line and the
      // payload's audioProof:"ingest-only" must make it impossible to
      // confuse with the full proof.
      console.log("  browser fallback: audio render not verifiable in this environment (ingest-only)");
    }
  } finally {
    if (server) server.close();
    fs.rmSync(bundleDir, { recursive: true, force: true });
  }
});

// --- Suite 27: browser PCM asset transport -----------------------------------

/** Node-side golden for the PCM asset probe: decode the committed asset
 *  exactly as the host does (PCM16 LE -> Float32 /32768, looping) and FNV-1a
 *  the raw Float32 bytes of every seam-aligned chunk the probe could observe
 *  as its "first wrapped post". The probe wraps the worklet port AFTER the
 *  asset resolves, and the initial fill's first 3200-sample chunk is posted
 *  before the wrapper exists — so the first OBSERVED chunk is one of the
 *  seam-aligned spans of the looping stream (deterministic per environment,
 *  both accepted). A browser that decoded through any MP3/WAV path could not
 *  reproduce any of these checksums. */
function computePcmAssetExpectation() {
  const buf = fs.readFileSync(PCM_ASSET);
  const totalSamples = buf.length / 2;
  const decodeLooped = (offset, len) => {
    const floats = new Float32Array(len);
    for (let i = 0; i < len; i++) floats[i] = buf.readInt16LE(((offset + i) % totalSamples) * 2) / 32768;
    return floats;
  };
  const crcOf = (floats) => fnv1a(new Uint8Array(floats.buffer, floats.byteOffset, floats.byteLength));
  // Chunk seams for a 4000-sample asset with 3200-sample chunks + loop wrap:
  // spans [0,3200) (len 3200) and [3200,4000) (len 800), repeating forever.
  const acceptedChunks = [
    { len: 3200, crcs: new Set([crcOf(decodeLooped(0, 3200))]) },
    { len: 800, crcs: new Set([crcOf(decodeLooped(3200, 800))]) },
  ];
  return {
    samples: totalSamples,
    durationUs: String(BigInt(Math.round((totalSamples * 1e6) / SAMPLE_RATE))),
    acceptedChunks,
  };
}

/** Self-contained data: variant of the PCM asset probe: the SAME probe page
 *  with window.__PCM_ASSET_PROBE_INLINE__ injected before its module script
 *  (host module blob, worklet blob, minimal wasm bytes, PCM asset bytes —
 *  all inline base64). Identical probe logic; only the loading path differs
 *  (exercises options.pcmAssetBytes instead of the http fetch). */
function buildPcmAssetDataProbeUrl(bundleDir) {
  const html = fs.readFileSync(PCM_ASSET_PROBE_PAGE, "utf8");
  const inline = {
    hostB64: fs.readFileSync(HOST_MODULE).toString("base64"),
    workletB64: fs.readFileSync(path.join(webHostDir, "pcm-worklet.js")).toString("base64"),
    wasmB64: fs.readFileSync(path.join(bundleDir, "assets", "minimal.wasm")).toString("base64"),
    pcmB64: fs.readFileSync(PCM_ASSET).toString("base64"),
  };
  const inject = `<script>window.__PCM_ASSET_PROBE_INLINE__=${JSON.stringify(inline)};</script>`;
  const marker = '<script type="module">';
  const at = html.indexOf(marker);
  if (at === -1) throw new Error("run-tests: pcm-asset-probe.html has no module script marker to inject before");
  const patched = html.slice(0, at) + inject + html.slice(at);
  return `data:text/html;base64,${Buffer.from(patched).toString("base64")}`;
}

suite("browser: PCM asset transport (fetch -> bounded chunks -> AudioWorklet)", async () => {
  if (SKIP_BROWSER) {
    console.log("  skipped by --skip-browser / PASSPORT_SKIP_BROWSER=1");
    return;
  }
  const bundleDir = fs.mkdtempSync(path.join(os.tmpdir(), "passport-pcm-browser-"));
  let server = null;
  try {
    const res = spawnSync(process.execPath, [MAKE_BUNDLE_TOOL, bundleDir], { encoding: "utf8" });
    eq(res.status, 0, `pcm browser suite bundle assembly must succeed; stderr: ${res.stderr}`);
    // The asset-mode app: minimal wasm with NO passport imports (written into
    // the throwaway bundle dir; never into the committed tree).
    fs.writeFileSync(path.join(bundleDir, "assets", "minimal.wasm"), buildMinimalPassportWasm());
    const expected = computePcmAssetExpectation();

    // Path 1: playwright against the http-served probe (the CI mechanism:
    //         the REAL http fetch of the normalized .pcm + AudioWorklet are
    //         REQUIRED here). Paths 2+3: chrome-headless-shell fallbacks.
    server = await startProbeServer(bundleDir);
    const url = `http://127.0.0.1:${server.address().port}/test/pcm-asset-probe.html`;
    let outcome = { path: null, mechanism: null, payload: null, note: null };
    try {
      const pw = await runProbeInPlaywright(url);
      if (pw.payload) outcome = pw;
      else if (pw.note) console.log(`  playwright unavailable: ${pw.note}`);
    } catch (err) {
      console.log(`  playwright path failed (${err && err.message ? err.message : err}); trying chrome-headless-shell`);
    }
    if (!outcome.payload) {
      outcome = runShellProbe(url, "http pcm-asset probe page", 8_000);
      if (!outcome.payload) {
        console.log(`  http pcm-asset probe did not complete (${outcome.note || "no payload"}); trying self-contained data: probe`);
        const dataUrl = buildPcmAssetDataProbeUrl(bundleDir);
        const notes = [];
        for (let attempt = 1; attempt <= DATA_PROBE_ATTEMPTS && !outcome.payload; attempt++) {
          if (attempt > 1) {
            await sleep(DATA_PROBE_RETRY_DELAY_MS);
            console.log(`  self-contained pcm data: probe attempt ${attempt}/${DATA_PROBE_ATTEMPTS}`);
          }
          const retried = runShellProbe(dataUrl, `pcm self-contained data: probe, attempt ${attempt}/${DATA_PROBE_ATTEMPTS}`, 20_000);
          if (retried.payload) {
            outcome = retried;
          } else {
            notes.push(retried.note || "no payload");
          }
        }
        if (!outcome.payload) outcome.note = notes.join("; ");
      }
    }
    ok(
      outcome.payload !== null,
      "no browser path produced a pcm-asset probe result" + (outcome.note ? `; attempts: ${outcome.note}` : ""),
    );
    const { payload, path: usedPath } = outcome;

    ok(payload.status === "ok", `pcm-asset probe must boot cleanly; payload: ${JSON.stringify(payload)}`);
    console.log(`  browser path: ${usedPath} [mechanism: ${outcome.mechanism}]${payload.inline ? " [inline]" : ""}`);

    // ---- asset facts: exact fetch + normalization state ----
    eq(payload.assetLoaded, true, "PCM asset must be fetched and resident in the browser");
    eq(payload.assetSamples, expected.samples, `asset sample count (${expected.samples})`);
    eq(payload.assetDurationUs, expected.durationUs, "asset duration_us fact");
    eq(payload.assetLooping, true, "asset looping on");
    ok(!payload.assetError, `no asset error (got ${JSON.stringify(payload.assetError)})`);

    // ---- transport: AudioWorklet required on the playwright (CI) path ----
    ok(
      payload.audioKind === "worklet" || payload.audioKind === "script",
      `audioKind must be worklet or script, got ${JSON.stringify(payload.audioKind)}` +
        (payload.audioReason ? ` (audioReason: ${payload.audioReason})` : ""),
    );
    if (outcome.mechanism === "playwright") {
      eq(payload.audioKind, "worklet", "the CI path must use the real AudioWorklet transport for the PCM asset");
    }
    // ---- exact decode: the first OBSERVED posted chunk byte-equals a
    //      node-side PCM16 decode of a seam-aligned span of the looping
    //      artifact (worklet path only — SP has no chunks) ----
    if (payload.audioKind === "worklet") {
      const accepted = expected.acceptedChunks.find((c) => c.len === payload.firstChunkLen);
      ok(accepted !== undefined, `first observed chunk length must be a seam-aligned span (800 or 3200); got ${payload.firstChunkLen}`);
      ok(
        accepted && accepted.crcs.has(payload.firstChunkCrc),
        `first chunk Float32 bytes must equal a node-side PCM16 LE decode of the looping artifact ` +
          `(len=${payload.firstChunkLen} crc=${payload.firstChunkCrc}; no MP3/WAV decoder can produce these bytes)`,
      );
    }
    ok(typeof payload.audioFilled === "number" && payload.audioFilled > 0, `chunks reached the transport (audioFilled=${payload.audioFilled})`);
    ok(payload.dropped === 0, `worklet ring must never overflow (dropped=${payload.dropped})`);

    // ---- consumption + loop refill (2+ passes over the 0.25 s asset) ----
    const loopRequired = outcome.mechanism === "playwright";
    if (loopRequired || payload.consumed > 0) {
      ok(
        payload.consumed > 8000,
        `render side must consume past 2 full asset passes (consumed=${payload.consumed} > 8000 = 2x4000)`,
      );
      ok(payload.loops >= 2, `consumption-based loop count must be >= 2 (loops=${payload.loops})`);
    } else {
      console.log("  browser fallback: asset render not verifiable in this environment (ingest-only)");
    }

    // ---- frames + canvas keep running while audio is active ----
    ok(payload.framesDuring > 0, `wasm frames must continue while audio runs (framesDuring=${payload.framesDuring})`);
    eq(
      payload.presentedDuring,
      payload.framesDuring,
      "every in-wait frame presented to the canvas (minimal app is always dirty)",
    );
    eq(payload.framesBefore, 5, "pre-audio deterministic tick count");

    // ---- mute never stops the playback position ----
    eq(payload.muted, true, "probe muted the host partway (after 1600 consumed)");
    ok(payload.posAtMuteUs !== null, "position captured at mute time");
    ok(
      Number(payload.posEndUs) > Number(payload.posAtMuteUs),
      `playback position advanced while muted (posAtMute=${payload.posAtMuteUs} -> posEnd=${payload.posEndUs})`,
    );
    console.log(
      `  asset proof: kind=${payload.audioKind} samples=${payload.assetSamples} consumed=${payload.consumed} ` +
        `loops=${payload.loops} framesDuring=${payload.framesDuring} mutedPos=${payload.posAtMuteUs}->${payload.posEndUs} ` +
        `waitMs=${payload.audioWaitMs}` +
        (payload.audioWorkletError ? ` workletError=${payload.audioWorkletError}` : ""),
    );
  } finally {
    if (server) server.close();
    fs.rmSync(bundleDir, { recursive: true, force: true });
  }
});

// --- Suite 28: browser DOM auto-boot (the SDK's own index.html) --------------

/** Serve the DOM auto-boot fixture bundle EXACTLY as the distribution contract
 *  describes it — one directory containing index.html, passport-host.js,
 *  pcm-worklet.js, app.wasm and assets/test.pcm — with NO probe page and NO
 *  query routing of its own: the page under test is the unmodified SDK-owned
 *  hosts/web/index.html, and every URL parameter goes to the host's own
 *  generic parser. app.wasm is the minimal no-import module (the fixture wasm
 *  declares passport.host_pcm_write and is rejected by an asset-configured
 *  host — producer-mode exclusivity). */
function startAutoBootServer(bundleDir) {
  const routes = {
    "/index.html": path.join(webHostDir, "index.html"),
    "/passport-host.js": HOST_MODULE,
    "/pcm-worklet.js": path.join(webHostDir, "pcm-worklet.js"),
    "/app.wasm": path.join(bundleDir, "app.wasm"),
    "/assets/test.pcm": path.join(bundleDir, "assets", "test.pcm"),
    "/favicon.ico": null, // 204: keep the console free of favicon-404 noise
  };
  const server = http.createServer((req, res) => {
    const urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
    if (urlPath === "/favicon.ico") {
      res.writeHead(204);
      res.end();
      return;
    }
    const filePath = routes[urlPath] || null;
    if (!filePath || !fs.existsSync(filePath)) {
      res.writeHead(404, { "content-type": "text/plain" });
      res.end("not found");
      return;
    }
    const type = filePath.endsWith(".wasm")
      ? "application/wasm"
      : filePath.endsWith(".html")
        ? "text/html; charset=utf-8"
        : filePath.endsWith(".js")
          ? "text/javascript"
          : "application/octet-stream";
    res.writeHead(200, { "content-type": type });
    res.end(fs.readFileSync(filePath));
  });
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => resolve(server));
  });
}

/** Playwright run of the DOM auto-boot page. Unlike runProbeInPlaywright there
 *  is no #probe-result element: the page is the untouched SDK index.html, so
 *  every fact is read back through globalThis.__passportHost (installed by the
 *  auto-boot itself — its mere existence is the no-ReferenceError proof) and
 *  through the page's #passport-status element. Returns
 *  { payload, pageErrors, consoleErrors } or null when playwright is absent. */
async function runAutoBootInPlaywright(url, waitFor) {
  const pw = await loadPlaywright();
  if (!pw) return null;
  if (!pw.chromium || typeof pw.chromium.launch !== "function") return null;
  const browser = await pw.chromium.launch({ headless: true, args: BROWSER_LAUNCH_FLAGS });
  const facts = { payload: null, pageErrors: [], consoleErrors: [] };
  try {
    const page = await browser.newPage();
    page.on("pageerror", (err) => facts.pageErrors.push(String(err)));
    page.on("console", (msg) => {
      if (msg.type() === "error") facts.consoleErrors.push(msg.text());
    });
    await page.goto(url, { waitUntil: "load", timeout: 30_000 });
    // Boot proof: __passportHost appears ONLY after autoBootFromDom's own
    // createHost() resolved. While the 0.0.2 ReferenceError is live this
    // wait times out: the handler dies before createHost is ever called.
    await page.waitForFunction(() => globalThis.__passportHost !== undefined, null, { timeout: 45_000 });
    if (waitFor) {
      // In-page polling (resumeAudio per poll mirrors the probe pages: the
      // launcher flag already allows autoplay, this is belt-and-braces).
      await page.waitForFunction(
        () => {
          const host = globalThis.__passportHost;
          if (!host) return false;
          host.resumeAudio();
          return host.audioAssetLoaded && host.audioAssetLoops >= 2;
        },
        null,
        { timeout: 45_000, polling: 100 },
      );
    }
    // Snapshot after a wall-clock beat so "frames continue" has a delta to
    // observe (rAF loop is running: minimal wasm is always dirty, so every
    // tick also presented to the canvas).
    facts.payload = await page.evaluate(
      () =>
        new Promise((resolve) => {
          const host = globalThis.__passportHost;
          const frames0 = host.frameCount;
          const canvas = document.getElementById("passport-canvas");
          setTimeout(() => {
            resolve({
              status: document.getElementById("passport-status").textContent,
              audioKind: host.audio.kind,
              audioReason: host.audio.reason,
              audioWorkletError: host.audio.workletError,
              hasFrameExport: typeof host.exports.passport_frame === "function",
              hasMemory: host.memory.buffer instanceof ArrayBuffer,
              frameCountAtSnapshot: frames0,
              framesDuring: host.frameCount - frames0,
              fpsText: document.getElementById("passport-fps").textContent,
              canvasWidth: canvas.width,
              canvasHeight: canvas.height,
              assetConfigured: host.audioAsset.configured,
              assetLoaded: host.audioAssetLoaded,
              assetSamples: host.audioAssetSamples,
              assetLooping: host.audioAssetLooping,
              assetError: host.audioAsset.error,
              loops: host.audioAssetLoops,
              posUs: String(host.playbackPosUs()),
              dropped: host.audio.dropped,
            });
          }, 400);
        }),
    );
  } finally {
    await browser.close().catch(() => {});
  }
  return facts;
}

/** chrome-headless-shell fallback: dump the DOM of the auto-boot page and read
 *  the #passport-status line the host itself maintains — "running (audio:
 *  worklet)" after a clean boot, "boot failed: ..." when autoBootFromDom's
 *  catch handler fired (e.g. the 0.0.2 ReferenceError). Degraded proof: no
 *  audio-consumption facts, page-load + status text only (never used by CI). */
function runShellAutoBootStatus(url) {
  const bin = findHeadlessShell();
  if (!bin) return null;
  const res = spawnSync(
    bin,
    [
      ...BROWSER_LAUNCH_FLAGS,
      "--virtual-time-budget=20000",
      "--timeout=20000",
      "--dump-dom",
      url,
    ],
    { encoding: "utf8", timeout: 80_000, maxBuffer: 64 * 1024 * 1024 },
  );
  const m = res.stdout ? /<div id="passport-status">([^<]*)<\/div>/.exec(res.stdout) : null;
  return m ? m[1].trim() : null;
}

suite("browser: DOM auto-boot PCM asset mode (SDK index.html + ?pcm=&pcmLoop=1)", async () => {
  if (SKIP_BROWSER) {
    console.log("  skipped by --skip-browser / PASSPORT_SKIP_BROWSER=1");
    return;
  }
  const bundleDir = fs.mkdtempSync(path.join(os.tmpdir(), "passport-autoboot-"));
  let server = null;
  try {
    // Fixture bundle: make-bundle assembles app.wasm + assets/test.pcm, then
    // app.wasm is replaced by the minimal no-import module (asset-mode boot:
    // the streaming fixture wasm would be rejected at boot on purpose).
    const res = spawnSync(process.execPath, [MAKE_BUNDLE_TOOL, bundleDir], { encoding: "utf8" });
    eq(res.status, 0, `auto-boot suite bundle assembly must succeed; stderr: ${res.stderr}`);
    fs.writeFileSync(path.join(bundleDir, "app.wasm"), buildMinimalPassportWasm());

    server = await startAutoBootServer(bundleDir);
    const base = `http://127.0.0.1:${server.address().port}`;
    const bootUrl = `${base}/index.html?pcm=./assets/test.pcm&pcmLoop=1`;

    let facts = null;
    try {
      facts = await runAutoBootInPlaywright(bootUrl, true);
    } catch (err) {
      console.log(`  playwright auto-boot path failed (${err && err.message ? err.message : err}); trying chrome-headless-shell`);
    }
    if (facts && facts.payload) {
      const p = facts.payload;
      console.log(
        `  auto-boot path: playwright [kind=${p.audioKind} samples=${p.assetSamples} loops=${p.loops} ` +
          `pos=${p.posUs}us framesDuring=${p.framesDuring} fps=${p.fpsText}]`,
      );

      // ---- no ReferenceError / no boot failure (the 0.0.2 regression) ----
      eq(facts.pageErrors.length, 0, `the page must throw NOTHING (got ${JSON.stringify(facts.pageErrors)})`);
      const bootFailures = facts.consoleErrors.filter(
        (line) => line.includes("ReferenceError") || line.includes("[passport-host] boot failed"),
      );
      eq(bootFailures.length, 0, `no ReferenceError / boot-failed console errors (got ${JSON.stringify(bootFailures)})`);
      ok(p.status.startsWith("running"), `#passport-status must say running (got [${p.status}])`);

      // ---- globalThis.__passportHost exists AND app.wasm started ----
      ok(p.hasFrameExport && p.hasMemory, "the host object exposes the live wasm instance (memory + passport_frame)");
      ok(p.frameCountAtSnapshot > 0, `app.wasm must have started ticking before the snapshot (${p.frameCountAtSnapshot} frames)`);

      // ---- PCM asset configured from the URL, loaded, looping ----
      eq(p.assetConfigured, true, "?pcm= must configure PCM asset mode through the URL");
      eq(p.assetLoaded, true, "the PCM asset at ./assets/test.pcm must be fetched and resident");
      eq(p.assetSamples, 4000, "asset sample count (8000-byte test.pcm / 2)");
      eq(p.assetLooping, true, "?pcmLoop=1 must enable sample-exact looping");
      ok(!p.assetError, `no asset error (got ${JSON.stringify(p.assetError)})`);

      // ---- AudioWorklet transport (the CI mechanism gets the real one) ----
      eq(p.audioKind, "worklet", "the DOM auto-boot must reach the real AudioWorklet transport");

      // ---- PCM samples consumed AND the asset LOOPS ----
      ok(Number(p.posUs) > 0, `playback position must be consumption-driven and > 0 (got ${p.posUs})`);
      ok(p.loops >= 2, `consumption must pass 2 full asset passes (loops=${p.loops} >= 2)`);
      eq(p.dropped, 0, "worklet ring must never overflow while looping");

      // ---- canvas frames continue while audio plays ----
      eq(p.canvasWidth, 120, "canvas backing-store width");
      eq(p.canvasHeight, 160, "canvas backing-store height");
      ok(p.framesDuring > 0, `canvas frames must continue during the 400 ms audio snapshot (got ${p.framesDuring})`);

      // ---- regression guard: the NO-QUERY DOM boot must stay clean too
      //      (the 0.0.2 ReferenceError fired before createHost on EVERY DOM
      //      boot, with or without ?pcm) ----
      const plain = await runAutoBootInPlaywright(`${base}/index.html`, false);
      ok(plain && plain.payload, "the no-query auto-boot page must also produce a host");
      if (plain && plain.payload) {
        const q = plain.payload;
        ok(q.status.startsWith("running"), `no-query boot status must be running (got [${q.status}])`);
        eq(q.assetConfigured, false, "no ?pcm -> streamed mode (no asset configured)");
        ok(q.frameCountAtSnapshot > 0, "no-query boot keeps ticking frames");
        eq(
          plain.pageErrors.length,
          0,
          `the no-query page must throw NOTHING (got ${JSON.stringify(plain.pageErrors)})`,
        );
      }
    } else {
      // Local fallback ONLY (never CI): the status line the host itself
      // renders is the whole proof — "running (audio: ...)" after a clean
      // auto-boot, "boot failed: ReferenceError: ..." while 0.0.2 is live.
      const status = runShellAutoBootStatus(bootUrl);
      ok(status !== null, "chrome-headless-shell produced no auto-boot DOM to inspect");
      ok(
        status !== null && status.startsWith("running"),
        `auto-boot must complete without the boot-failed handler (status [${status}])`,
      );
      ok(status !== null && !status.includes("ReferenceError"), `no ReferenceError in the status line (got [${status}])`);
      console.log("  auto-boot fallback (chrome-headless-shell): status-line proof only, no audio-consumption proof");
    }
  } finally {
    if (server) server.close();
    fs.rmSync(bundleDir, { recursive: true, force: true });
  }
});

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

// Prerequisite check with the exact recovery commands.
if (!fs.existsSync(RELEASE_WASM) || !fs.existsSync(DEBUG_WASM)) {
  console.error("run-tests: fixture wasm artifacts missing. From the repo root, run:");
  console.error("  moon build --target wasm --release   # " + path.relative(repoRoot, RELEASE_WASM));
  console.error("  moon build --target wasm             # " + path.relative(repoRoot, DEBUG_WASM));
  process.exit(2);
}
if (!fs.existsSync(PCM_ASSET)) {
  console.log("run-tests: hosts/web/assets/test.pcm missing; generating it via gen-test-pcm.mjs");
  const r = spawnSync(process.execPath, [GEN_PCM_TOOL], { stdio: "inherit" });
  if (r.status !== 0) process.exit(r.status ?? 1);
}

console.log(`passport wasm-host integration tests (node ${process.version})`);
console.log(`  release wasm: ${path.relative(repoRoot, RELEASE_WASM)}`);
console.log(`  debug   wasm: ${path.relative(repoRoot, DEBUG_WASM)}`);
console.log(`  pcm asset  : ${path.relative(repoRoot, PCM_ASSET)}`);

let failed = 0;
for (const { name, fn } of suites) {
  process.stdout.write(`\nRUN  ${name}\n`);
  try {
    await fn();
    console.log(`PASS ${name}`);
  } catch (err) {
    failed += 1;
    console.log(`FAIL ${name}`);
    const text = String((err && err.stack) || err);
    for (const line of text.split("\n")) console.log(`  ${line}`);
  }
}

console.log(failed === 0 ? "\nALL SUITES PASSED" : `\n${failed} SUITE(S) FAILED`);
process.exit(failed === 0 ? 0 : 1);
