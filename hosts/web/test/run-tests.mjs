#!/usr/bin/env node
/** End-to-end Web Host, Sound runtime, CLI, and real-browser gates. */

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { registerCliFixtureSuites } from "./cli-fixture-suites.mjs";
import { BROWSER_LAUNCH_FLAGS, loadPlaywright, startStaticServer } from "./browser-common.mjs";
import { buildMinimalPassportWasm } from "./minimal-wasm.mjs";

const testDir = path.dirname(fileURLToPath(import.meta.url));
const webHostDir = path.resolve(testDir, "..");
const repoRoot = path.resolve(webHostDir, "..", "..");
const RELEASE_WASM = path.join(repoRoot, "_build", "wasm", "release", "build", "fixture", "fixture.wasm");
const DEBUG_WASM = path.join(repoRoot, "_build", "wasm", "debug", "build", "fixture", "fixture.wasm");
const SOUND_HOST_WASM = path.join(
  repoRoot, "_build", "wasm", "debug", "build", "sound_host_fixture", "sound_host_fixture.wasm",
);
const HOST_MODULE = path.join(webHostDir, "passport-host.js");
const SKIP_BROWSER = process.argv.includes("--skip-browser") || process.env.PASSPORT_SKIP_BROWSER === "1";

class SuiteError extends Error {}
const suites = [];
const suite = (name, run) => suites.push({ name, run });
function ok(condition, message) {
  if (!condition) throw new SuiteError(message);
}
function eq(actual, expected, message) {
  if (!Object.is(actual, expected)) {
    throw new SuiteError(`${message}: expected ${String(expected)}, got ${String(actual)}`);
  }
}
function eqText(actual, expected, message) {
  if (actual !== expected) throw new SuiteError(`${message}: expected [${expected}], got [${actual}]`);
}

function requireArtifacts() {
  const missing = [RELEASE_WASM, DEBUG_WASM, SOUND_HOST_WASM].filter((file) => !fs.existsSync(file));
  if (missing.length > 0) {
    throw new Error(
      `missing wasm test artifacts:\n${missing.join("\n")}\n` +
        "run: moon build --target wasm --release && moon build --target wasm",
    );
  }
}

function soundBank(samplesBySound) {
  const headerSize = 16;
  const entrySize = 8;
  const payloadOffset = headerSize + samplesBySound.length * entrySize;
  const totalSamples = samplesBySound.reduce((sum, samples) => sum + samples.length, 0);
  const buffer = new ArrayBuffer(payloadOffset + totalSamples * 2);
  const bytes = new Uint8Array(buffer);
  const view = new DataView(buffer);
  bytes.set([0x41, 0x50, 0x53, 0x42]);
  view.setUint16(4, 1, true);
  view.setUint16(6, headerSize, true);
  view.setUint32(8, samplesBySound.length, true);
  view.setUint16(12, entrySize, true);
  let offset = payloadOffset;
  for (let id = 0; id < samplesBySound.length; id++) {
    const samples = samplesBySound[id];
    view.setUint32(headerSize + id * entrySize, offset, true);
    view.setUint32(headerSize + id * entrySize + 4, samples.length, true);
    new Int16Array(buffer, offset, samples.length).set(samples);
    offset += samples.length * 2;
  }
  return buffer;
}

function fakeCanvas() {
  const puts = [];
  const ctx = {
    putImageData(image, dx, dy) { puts.push({ image, dx, dy }); },
    imageSmoothingEnabled: true,
  };
  return {
    canvas: { width: 0, height: 0, style: {}, getContext: () => ctx },
    puts,
  };
}

requireArtifacts();
const hostModule = await import(`${pathToFileURL(HOST_MODULE).href}?pr6=${Date.now()}`);

suite("abi: legacy single-PCM imports are absent", () => {
  for (const [name, file] of [["release", RELEASE_WASM], ["debug", DEBUG_WASM]]) {
    const module = new WebAssembly.Module(fs.readFileSync(file));
    const names = WebAssembly.Module.imports(module).map((entry) => `${entry.module}.${entry.name}`);
    ok(!names.includes("passport.host_pcm_write"), `${name} wasm must not import host_pcm_write`);
    ok(!names.includes("passport.host_playback_pos_us"), `${name} wasm must not import the global playback clock`);
  }
});

suite("host: lifecycle, framebuffer, input, and master output", async () => {
  const { canvas } = fakeCanvas();
  const gain = { gain: { value: 0 }, connect() {} };
  const host = await hostModule.createHost({
    wasmBytes: fs.readFileSync(RELEASE_WASM),
    soundBankBytes: soundBank([]),
    canvas,
    batteryPercent: 82,
    audioContextFactory: () => ({ currentTime: 0, destination: {}, createGain: () => gain }),
  });
  eq(host.frameCount, 0, "frame count starts at zero");
  eq(host.volume, 70, "fixture startup mirrors its master volume");
  eq(host.muted, false, "fixture startup mirrors its mute state");
  eq(gain.gain.value, 0.7, "GainNode follows master volume");
  const first = host.tick(0n);
  ok(first && first.presented, "one tick presents the framebuffer");
  eq(canvas.width, 240, "canvas width");
  eq(canvas.height, 320, "canvas height");
  host.imports.passport.host_set_backlight(35);
  eq(host.imports.passport.host_backlight_level(), 35, "display light level is queryable");
  eq(canvas.style.filter, "brightness(35%)", "Web presentation applies light level");
  eq(host.getFramebufferView()[0], 0xf800, "the presented framebuffer is readable");
  host.queueInput(hostModule.BUTTON.Down, true);
  host.tick(16_667n);
  eq(host.getFramebufferView()[28 * 240], 0xffe0, "queued Down reaches application input");
  host.setVolume(150);
  eq(host.volume, 100, "master volume clamps high");
  host.setMuted(true);
  eq(host.muted, true, "master mute updates");
  eq(gain.gain.value, 0, "master mute silences the GainNode");
  ok(!("pcmStats" in host), "legacy PCM statistics surface is gone");
  ok(!("audioAsset" in host), "legacy PCM asset surface is gone");
  ok(!("playbackPosUs" in host), "global playback position surface is gone");
  host.dispose();
});

suite("host: APSB validation fails fast", async () => {
  const malformed = new Uint8Array(soundBank([]).byteLength + 1);
  malformed.set(new Uint8Array(soundBank([])));
  let error = null;
  try {
    await hostModule.createHost({ wasmBytes: buildMinimalPassportWasm(), soundBankBytes: malformed });
  } catch (caught) {
    error = caught;
  }
  ok(error && String(error.message).includes("trailing"), "trailing bank bytes must fail observably");
});

suite("host: same Sound creates independent Playback handles", async () => {
  let processor = null;
  const ctx = {
    currentTime: 0,
    destination: {},
    createGain: () => ({ gain: { value: 0 }, connect() {} }),
    createScriptProcessor: (size) => {
      processor = { bufferSize: size, onaudioprocess: null, connect() {} };
      return processor;
    },
  };
  const sound0 = new Int16Array(5000).fill(10000);
  const sound1 = new Int16Array(6000).fill(-4000);
  const host = await hostModule.createHost({
    wasmBytes: buildMinimalPassportWasm(),
    soundBankBytes: soundBank([sound0, sound1]),
    audioContextFactory: () => ctx,
  });
  const api = host.imports.passport;
  ok(!("host_pcm_write" in api), "legacy streamed PCM import is absent");
  ok(!("host_playback_pos_us" in api), "legacy global position import is absent");
  const first = api.host_sound_play(0, 1);
  const second = api.host_sound_play(0, 1);
  ok(first > 0 && second > 0 && first !== second, "overlapping plays receive distinct handles");
  const extras = [];
  for (let i = 0; i < 6; i++) extras.push(api.host_sound_play(1, 0));
  ok(extras.every((handle) => handle > 0), "all eight playback slots are usable");
  eq(api.host_sound_play(1, 0), -1, "a full table fails without stealing");
  for (const handle of extras) api.host_sound_stop(handle);
  const pull = () => {
    const out = new Float32Array(processor.bufferSize);
    processor.onaudioprocess({ outputBuffer: { getChannelData: () => out } });
    return out;
  };
  eq(pull()[0], 20000 / 32768, "two sources mix sample-for-sample");
  eq(api.host_sound_position_us(first), 256000n, "first position is per-playback");
  eq(api.host_sound_position_us(second), 256000n, "second position is independent");
  api.host_sound_pause(first);
  pull();
  eq(api.host_sound_position_us(first), 256000n, "paused playback stays fixed");
  api.host_sound_resume(first);
  pull();
  ok(api.host_sound_position_us(first) !== 256000n, "resumed playback advances");
  api.host_sound_stop(first);
  eq(api.host_sound_position_us(first), -1n, "stopped handles expire");
  const oneShot = api.host_sound_play(1, 0);
  pull();
  pull();
  eq(api.host_sound_position_us(oneShot), -1n, "one-shot retires at EOF");
  host.dispose();
});

suite("host: microphone records PCM16 while sound output remains live", async () => {
  let micProcessor = null;
  let soundProcessor = null;
  let trackStops = 0;
  const ctx = {
    sampleRate: 48000,
    currentTime: 0,
    destination: {},
    resume: async () => {},
    createGain: () => ({ gain: { value: 0 }, connect() {} }),
    createMediaStreamSource: () => ({ connect() {}, disconnect() {} }),
    createScriptProcessor: (size, inputs) => {
      const node = { bufferSize: size, onaudioprocess: null, connect() {}, disconnect() {} };
      if (inputs) micProcessor = node;
      else soundProcessor = node;
      return node;
    },
  };
  const host = await hostModule.createHost({
    wasmBytes: buildMinimalPassportWasm(),
    soundBankBytes: soundBank([new Int16Array(5000).fill(1234)]),
    audioContextFactory: () => ctx,
    mediaDevices: { getUserMedia: async () => ({ getTracks: () => [{ stop: () => trackStops++ }] }) },
  });
  const api = host.imports.passport;
  eq(api.host_capture_status(), 1, "capture is initially idle");
  eq(api.host_capture_start(), 2, "permission is asynchronous");
  await new Promise((resolve) => setImmediate(resolve));
  eq(api.host_capture_status(), 3, "permission starts recording");
  ok(api.host_sound_play(0, 1) > 0, "sound output remains available during capture");
  const input = new Float32Array(480).fill(0.5);
  const output = new Float32Array(480).fill(1);
  micProcessor.onaudioprocess({
    inputBuffer: { getChannelData: () => input },
    outputBuffer: { getChannelData: () => output },
  });
  ok(output.every((sample) => sample === 0), "capture node never echoes microphone to speakers");
  const count = api.host_capture_read(1024);
  ok(count >= 159 && count <= 161, "48 kHz input resamples to 16 kHz");
  const captured = new DataView(host.memory.buffer).getInt16(196608, true);
  eq(captured, 16384, "host writes signed PCM16 samples");
  const played = new Float32Array(soundProcessor.bufferSize);
  soundProcessor.onaudioprocess({ outputBuffer: { getChannelData: () => played } });
  eq(played[0], 1234 / 32768, "speaker playback continues during microphone capture");
  api.host_capture_stop();
  eq(api.host_capture_status(), 1, "stop returns to idle");
  eq(trackStops, 1, "stop releases the microphone track once");
  host.dispose();
});

suite("host: microphone permission denial and canceled requests stay observable", async () => {
  const makeContext = () => ({
    sampleRate: 16000, destination: {},
    createGain: () => ({ gain: { value: 0 }, connect() {} }),
    createScriptProcessor: () => ({ connect() {}, disconnect() {} }),
  });
  const denied = await hostModule.createHost({
    wasmBytes: buildMinimalPassportWasm(), soundBankBytes: soundBank([]),
    audioContextFactory: makeContext,
    mediaDevices: { getUserMedia: async () => { throw Object.assign(new Error("denied"), { name: "NotAllowedError" }); } },
  });
  eq(denied.imports.passport.host_capture_start(), 2, "permission request begins");
  await new Promise((resolve) => setImmediate(resolve));
  eq(denied.imports.passport.host_capture_status(), 4, "denial is distinct from failure");
  denied.dispose();

  let grant;
  let stops = 0;
  const pending = await hostModule.createHost({
    wasmBytes: buildMinimalPassportWasm(), soundBankBytes: soundBank([]),
    audioContextFactory: makeContext,
    mediaDevices: { getUserMedia: () => new Promise((resolve) => { grant = resolve; }) },
  });
  eq(pending.imports.passport.host_capture_start(), 2, "pending request begins");
  pending.imports.passport.host_capture_stop();
  grant({ getTracks: () => [{ stop: () => stops++ }] });
  await new Promise((resolve) => setImmediate(resolve));
  eq(pending.imports.passport.host_capture_status(), 1, "canceled grant cannot resume recording");
  eq(stops, 1, "canceled grant releases its track");
  pending.dispose();
});

suite("host: explicit sleep pauses frames and reports button or timer wake", async () => {
  const host = await hostModule.createHost({
    wasmBytes: buildMinimalPassportWasm(), soundBankBytes: soundBank([]),
  });
  const power = host.imports.passport;
  eq(power.host_wake_reason(), 0, "no wake cause before sleep");
  eq(power.host_power_request(-1), 1, "application sleep request is accepted");
  eq(power.host_power_request(-1), 0, "a duplicate request is rejected");
  host.tick(10n);
  eq(host.sleeping, true, "sleep starts after the current frame");
  const frames = host.frameCount;
  host.tick(20n);
  eq(host.frameCount, frames, "sleep stops application frames");
  host.queueInput(hostModule.BUTTON.Ok, true);
  eq(power.host_wake_reason(), 1, "button wake cause is visible");
  host.tick(30n);
  eq(host.frameCount, frames + 1, "frames resume after button wake");
  eq(power.host_power_request(5), 1, "timed sleep request is accepted");
  eq(power.host_wake_reason(), 0, "new request clears old cause");
  host.tick(40n);
  await new Promise((resolve) => setTimeout(resolve, 15));
  eq(power.host_wake_reason(), 2, "timer wake cause is visible");
  eq(host.sleeping, false, "timer resumes the Host");
  host.dispose();
});

suite("host: MoonBit Sound API reaches the Web runtime", async () => {
  let processor = null;
  const host = await hostModule.createHost({
    wasmBytes: fs.readFileSync(SOUND_HOST_WASM),
    soundBankBytes: soundBank([
      new Int16Array(5000).fill(3000),
      new Int16Array(1000).fill(7000),
    ]),
    audioContextFactory: () => ({
      currentTime: 0,
      destination: {},
      createGain: () => ({ gain: { value: 0 }, connect() {} }),
      createScriptProcessor: (size) => {
        processor = { bufferSize: size, onaudioprocess: null, connect() {} };
        return processor;
      },
    }),
  });
  host.tick(0n);
  const playbacks = host.soundPlaybacks;
  eq(playbacks.length, 3, "MoonBit starts one loop and two overlapping hits");
  eq(playbacks.filter((p) => p.soundId === 1).length, 2, "same Sound owns two handles");
  const out = new Float32Array(processor.bufferSize);
  processor.onaudioprocess({ outputBuffer: { getChannelData: () => out } });
  eq(out[0], 17000 / 32768, "MoonBit-started sounds mix correctly");
  eq(host.soundPlaybacks.length, 1, "both one-shots retire independently");
  host.dispose();
});

registerCliFixtureSuites({
  suite,
  ok,
  eq,
  eqText,
  SuiteError,
  repoRoot,
  webHostDir,
  skipBrowser: SKIP_BROWSER,
});

suite("browser: MoonBit Sound playbacks reach the real AudioWorklet", async () => {
  if (SKIP_BROWSER) {
    console.log("  skipped by --skip-browser / PASSPORT_SKIP_BROWSER=1");
    return;
  }
  const pw = await loadPlaywright();
  ok(pw && pw.chromium, "Playwright Chromium is required for the real-browser sound gate");
  const bundle = fs.mkdtempSync(path.join(os.tmpdir(), "passport-sound-browser-"));
  let server = null;
  let browser = null;
  try {
    for (const file of ["index.html", "passport-host.js", "sound-worklet.js"]) {
      fs.copyFileSync(path.join(webHostDir, file), path.join(bundle, file));
    }
    fs.copyFileSync(SOUND_HOST_WASM, path.join(bundle, "app.wasm"));
    fs.writeFileSync(
      path.join(bundle, "sounds.bank"),
      Buffer.from(soundBank([
        new Int16Array(32000).fill(3000),
        new Int16Array(32000).fill(7000),
      ])),
    );
    server = await startStaticServer(bundle);
    browser = await pw.chromium.launch({
      headless: true,
      args: [
        ...BROWSER_LAUNCH_FLAGS,
        "--use-fake-device-for-media-stream",
        "--use-fake-ui-for-media-stream",
      ],
    });
    const page = await browser.newPage();
    const pageErrors = [];
    page.on("pageerror", (error) => pageErrors.push(String(error)));
    await page.goto(`http://127.0.0.1:${server.address().port}/index.html`, { waitUntil: "load" });
    await page.waitForFunction(() => {
      const host = globalThis.__passportHost;
      if (!host) return false;
      host.resumeAudio();
      return host.audio.kind === "worklet" &&
        host.soundPlaybacks.length === 3 &&
        host.soundPlaybacks.every((playback) => playback.positionUs > 0n);
    }, null, { timeout: 45_000, polling: 100 });
    const facts = await page.evaluate(() => ({
      status: document.getElementById("passport-status").textContent,
      kind: globalThis.__passportHost.audio.kind,
      volume: globalThis.__passportHost.volume,
      muted: globalThis.__passportHost.muted,
      playbacks: globalThis.__passportHost.soundPlaybacks.map((p) => ({
        handle: p.handle,
        soundId: p.soundId,
        positionUs: String(p.positionUs),
      })),
    }));
    eq(pageErrors.length, 0, `browser page errors: ${pageErrors.join("; ")}`);
    ok(facts.status.startsWith("running"), "auto-boot status is running");
    eq(facts.kind, "worklet", "real browser uses AudioWorklet");
    eq(facts.volume, 80, "master volume reaches the Host");
    eq(facts.muted, false, "master mute reaches the Host");
    eq(facts.playbacks.length, 3, "three independent playbacks remain live");
    eq(new Set(facts.playbacks.map((p) => p.handle)).size, 3, "handles are distinct");
    const capture = await page.evaluate(async () => {
      const host = globalThis.__passportHost;
      const api = host.imports.passport;
      const initial = api.host_capture_start();
      const deadline = performance.now() + 10_000;
      while (api.host_capture_status() === 2 && performance.now() < deadline) {
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
      const status = api.host_capture_status();
      let count = 0;
      while (status === 3 && count === 0 && performance.now() < deadline) {
        await new Promise((resolve) => setTimeout(resolve, 50));
        count = api.host_capture_read(1024);
      }
      api.host_capture_stop();
      return { initial, status, count, stopped: api.host_capture_status() };
    });
    eq(capture.initial, 2, "real browser starts microphone permission request");
    eq(capture.status, 3, "real browser records fake microphone input");
    ok(capture.count > 0, "real browser capture delivers PCM samples");
    eq(capture.stopped, 1, "real browser releases microphone");
    eq(pageErrors.length, 0, `browser page errors: ${pageErrors.join("; ")}`);
  } finally {
    if (browser) await browser.close().catch(() => {});
    if (server) server.close();
    fs.rmSync(bundle, { recursive: true, force: true });
  }
});

console.log(`passport Web Host integration tests (node ${process.version})`);
let failed = 0;
for (const { name, run } of suites) {
  console.log(`\nRUN  ${name}`);
  try {
    await run();
    console.log(`PASS ${name}`);
  } catch (error) {
    failed += 1;
    console.error(`FAIL ${name}`);
    console.error(error && error.stack ? error.stack : error);
  }
}
if (failed > 0) {
  console.error(`\n${failed} SUITE(S) FAILED`);
  process.exit(1);
}
console.log("\nALL SUITES PASSED");
