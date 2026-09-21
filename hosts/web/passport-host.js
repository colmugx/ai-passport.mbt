/**
 * passport-host.js — application-agnostic WebAssembly host backend for the
 * AI Passport SDK. Implements the internal Wasm Host ABI (120x160 RGB565 LE
 * framebuffer plus sound-bank playback handles).
 *
 * Host responsibilities (the frozen JS/app split):
 *   - instantiate app.wasm, provide the "passport" imports, call _start() once
 *   - per frame: flush queued input events, call passport_frame(now_us:BigInt),
 *     blit the 120x160 RGB565 LE framebuffer when dirty, then consume
 *   - independent APSB sound playbacks mixed by an AudioWorklet (with a
 *     ScriptProcessorNode fallback), plus master volume/mute gain
 *   - permission-gated microphone capture as bounded PCM16 mono input
 *   - keyboard -> semantic buttons (Up/Down/Ok), host-facts HUD
 *
 * There is NO application logic here: nothing knows about any specific app,
 * sprites, BPM, or authored audio formats. It only sees the final APSB bank.
 *
 * Node-friendly: importable with no DOM and no AudioContext. All browser
 * capabilities are injected (options) or feature-detected. In a browser,
 * index.html loads this module and the auto-boot entry at the bottom runs the
 * host and installs globalThis.__passportHost.
 */

// ---------------------------------------------------------------------------
// Frozen ABI v0 constants (mirrored from src/hostabi)
// ---------------------------------------------------------------------------

/** Semantic buttons passed to passport_input(button, pressed). */
export const BUTTON = Object.freeze({ Up: 0, Down: 1, Ok: 2 });

export const FB_WIDTH = 120;
export const FB_HEIGHT = 160;
/** Framebuffer byte offset in the app's exported linear memory. */
export const FB_PTR = 0x1000; // 4096
/** Framebuffer byte length: 120 * 160 RGB565 uint16 LE, row-major. */
export const FB_LEN = FB_WIDTH * FB_HEIGHT * 2; // 38400
/** Normalized PCM stream format: PCM16 LE mono at this rate. */
export const SAMPLE_RATE = 16000;
const CAPTURE_PTR = 49152;
const CAPTURE_SAMPLES = 1024;
const CAPTURE_RING_SAMPLES = 8192;
const CAPTURE_STATUS = Object.freeze({
  Unavailable: 0, Idle: 1, Requesting: 2, Recording: 3, Denied: 4, Failed: 5,
});
/** App heap start; [0, 65536) is ABI-reserved. */
export const HEAP_START = 65536;

const SCRIPT_PROCESSOR_SAMPLES = 4096; // ScriptProcessor pull size (fallback transport)
const MAX_SOUND_PLAYBACKS = 8;
const SOUND_BANK_HEADER_SIZE = 16;
const SOUND_BANK_ENTRY_SIZE = 8;
const HUD_INTERVAL_MS = 250; // HUD refresh ~4x per second
const DEFAULT_SCALE = 3; // CSS integer scale
const DEFAULT_BATTERY_PERCENT = 82;

const REQUIRED_EXPORTS = [
  "_start",
  "passport_frame",
  "passport_input",
  "passport_fb_ptr",
  "passport_fb_len",
  "passport_frame_dirty",
  "passport_frame_consume",
];

// ---------------------------------------------------------------------------
// Boot checks, URL params, options helpers
// ---------------------------------------------------------------------------

/** The framebuffer and APSB PCM payload are little-endian; reject BE hosts. */
function requireLittleEndian() {
  const probe = new Uint32Array(new Uint8Array([0x01, 0x00, 0x00, 0x00]).buffer);
  if (probe[0] !== 1) {
    throw new Error(
      "passport-host: big-endian platform detected. ABI v0 stores the framebuffer " +
        "(RGB565 uint16) and APSB PCM payload little-endian; refusing to run rather " +
        "than corrupt output.",
    );
  }
}

function readUrlParams() {
  if (typeof location === "undefined" || !location || !location.search) return {};
  const out = {};
  const query = location.search.startsWith("?") ? location.search.slice(1) : location.search;
  for (const part of query.split("&")) {
    if (!part) continue;
    const eq = part.indexOf("=");
    const key = eq === -1 ? part : part.slice(0, eq);
    const value = eq === -1 ? "" : part.slice(eq + 1);
    try {
      out[decodeURIComponent(key)] = decodeURIComponent(value);
    } catch {
      out[key] = value;
    }
  }
  return out;
}

function normalizeBattery(value) {
  if (!Number.isFinite(value)) return DEFAULT_BATTERY_PERCENT;
  const v = Math.round(value);
  if (v === -1) return -1; // explicit "unavailable"
  return Math.min(100, Math.max(0, v));
}

/** ?battery=NN (0..100), ?battery=none (-1), default 82. options win over URL. */
function resolveBatteryPercent(options, params) {
  if (options.batteryPercent !== undefined) return normalizeBattery(Number(options.batteryPercent));
  const raw = params.battery;
  if (raw === undefined || raw === "") return DEFAULT_BATTERY_PERCENT;
  if (raw === "none") return -1;
  return normalizeBattery(Number(raw));
}

/** CSS integer scale: options.scale ?? ?scale=NN, default 3. */
function resolveScale(options, params) {
  const raw = options.scale !== undefined ? options.scale : params.scale;
  if (raw === undefined || raw === "") return DEFAULT_SCALE;
  const n = Math.floor(Number(raw));
  return Number.isFinite(n) && n >= 1 ? n : DEFAULT_SCALE;
}

function clampVolume(value) {
  if (value === undefined) return 100;
  const v = Math.round(Number(value));
  return Number.isFinite(v) ? Math.min(100, Math.max(0, v)) : 0;
}

function defaultNowUs() {
  const ms =
    typeof performance !== "undefined" && typeof performance.now === "function"
      ? performance.now()
      : Date.now();
  return BigInt(Math.round(ms * 1000));
}

function normalizeNowUs(state, nowUs) {
  if (nowUs === undefined) return state.nowUs();
  if (typeof nowUs === "bigint") return nowUs;
  if (typeof nowUs === "number" && Number.isFinite(nowUs)) return BigInt(Math.round(nowUs));
  throw new TypeError("tick: nowUs must be undefined, a BigInt, or a finite number of microseconds");
}

async function loadWasmBytes(options) {
  const bytes = options.wasmBytes;
  if (bytes) {
    if (bytes instanceof ArrayBuffer) return bytes;
    if (ArrayBuffer.isView(bytes)) return bytes;
    throw new TypeError("createHost: options.wasmBytes must be an ArrayBuffer or TypedArray");
  }
  const url = options.wasmUrl ?? options.fetch ?? new URL("./app.wasm", import.meta.url);
  const urlText = typeof url === "string" ? url : String(url);
  if (typeof fetch !== "function") {
    throw new Error(
      `passport-host: cannot load app.wasm from ${urlText}: fetch() unavailable here; pass options.wasmBytes`,
    );
  }
  const response = await fetch(urlText);
  if (!response.ok) {
    throw new Error(`passport-host: failed to fetch app.wasm at ${urlText}: HTTP ${response.status}`);
  }
  return response.arrayBuffer();
}

function emptySoundBankBytes() {
  const bytes = new Uint8Array(SOUND_BANK_HEADER_SIZE);
  bytes.set([0x41, 0x50, 0x53, 0x42, 0x01, 0x00, 0x10, 0x00]);
  bytes[12] = SOUND_BANK_ENTRY_SIZE;
  return bytes.buffer;
}

async function loadSoundBankBytes(options) {
  if (options.soundBankBytes !== undefined) {
    const input = options.soundBankBytes;
    if (!(input instanceof ArrayBuffer) && !ArrayBuffer.isView(input)) {
      throw new TypeError("createHost: options.soundBankBytes must be an ArrayBuffer or TypedArray");
    }
    return normalizeBinaryBytes(input);
  }
  if (options.wasmBytes !== undefined && options.soundBankUrl === undefined) {
    return emptySoundBankBytes();
  }
  const url = options.soundBankUrl ?? new URL("./sounds.bank", import.meta.url);
  if (typeof url !== "string" && !(url instanceof URL)) {
    throw new TypeError("createHost: options.soundBankUrl must be a string or URL");
  }
  if (typeof fetch !== "function") {
    throw new Error(`passport-host: cannot load sounds.bank from ${url}: fetch() unavailable here; pass options.soundBankBytes`);
  }
  const response = await fetch(String(url));
  if (!response.ok) {
    throw new Error(`passport-host: failed to fetch sounds.bank at ${url}: HTTP ${response.status}`);
  }
  return response.arrayBuffer();
}

function parseSoundBank(buffer) {
  if (!(buffer instanceof ArrayBuffer) || buffer.byteLength < SOUND_BANK_HEADER_SIZE) {
    throw new Error("passport-host: sounds.bank header is truncated");
  }
  const bytes = new Uint8Array(buffer);
  const view = new DataView(buffer);
  if (bytes[0] !== 0x41 || bytes[1] !== 0x50 || bytes[2] !== 0x53 || bytes[3] !== 0x42) {
    throw new Error("passport-host: sounds.bank magic is invalid");
  }
  if (view.getUint16(4, true) !== 1) throw new Error("passport-host: sounds.bank version is unsupported");
  if (view.getUint16(6, true) !== SOUND_BANK_HEADER_SIZE) {
    throw new Error("passport-host: sounds.bank header size is invalid");
  }
  if (view.getUint16(12, true) !== SOUND_BANK_ENTRY_SIZE) {
    throw new Error("passport-host: sounds.bank entry size is invalid");
  }
  if (view.getUint16(14, true) !== 0) throw new Error("passport-host: sounds.bank flags are unsupported");
  const count = view.getUint32(8, true);
  const indexEnd = SOUND_BANK_HEADER_SIZE + count * SOUND_BANK_ENTRY_SIZE;
  if (!Number.isSafeInteger(indexEnd) || indexEnd > buffer.byteLength) {
    throw new Error("passport-host: sounds.bank index is truncated");
  }
  const entries = new Array(count);
  let expectedOffset = indexEnd;
  for (let id = 0; id < count; id++) {
    const at = SOUND_BANK_HEADER_SIZE + id * SOUND_BANK_ENTRY_SIZE;
    const offset = view.getUint32(at, true);
    const sampleCount = view.getUint32(at + 4, true);
    const end = offset + sampleCount * 2;
    if (sampleCount === 0) throw new Error(`passport-host: sounds.bank entry ${id} is empty`);
    if (offset !== expectedOffset) throw new Error("passport-host: sounds.bank payload offsets are not contiguous");
    if (!Number.isSafeInteger(end) || end > buffer.byteLength) {
      throw new Error(`passport-host: sounds.bank entry ${id} payload is truncated`);
    }
    entries[id] = { offset, sampleCount };
    expectedOffset = end;
  }
  if (expectedOffset !== buffer.byteLength) {
    throw new Error("passport-host: sounds.bank contains trailing payload bytes");
  }
  return { bytes: buffer, entries };
}

/** Exact-copy a TypedArray input into its own ArrayBuffer (done once, at
 * load); ArrayBuffer input is authoritative already. */
function normalizeBinaryBytes(input) {
  if (input instanceof ArrayBuffer) return input;
  const out = new ArrayBuffer(input.byteLength);
  new Uint8Array(out).set(new Uint8Array(input.buffer, input.byteOffset, input.byteLength));
  return out;
}

// ---------------------------------------------------------------------------
// Sound-bank playback: independent handles, mixed only inside the Host
// ---------------------------------------------------------------------------

function postSoundCommand(state, message) {
  if (state.audio.kind === "worklet" && state.audio.node) {
    state.audio.node.port.postMessage(message);
  }
}

function soundPlay(state, soundId, looping) {
  const id = soundId | 0;
  if (!state.audio.enabled || state.audio.kind === "none") return -1;
  if (id < 0 || id >= state.soundBank.entries.length) return -1;
  if (state.soundPlaybacks.size >= MAX_SOUND_PLAYBACKS) return -1;
  let handle = state.nextSoundHandle;
  while (state.soundPlaybacks.has(handle)) {
    handle += 1;
    if (handle > 0x7fffffff) handle = 1;
  }
  state.nextSoundHandle = handle === 0x7fffffff ? 1 : handle + 1;
  const entry = state.soundBank.entries[id];
  state.soundPlaybacks.set(handle, {
    handle,
    soundId: id,
    looping: !!looping,
    paused: false,
    positionSamples: 0,
    cursor: 0,
    samples: new Int16Array(state.soundBank.bytes, entry.offset, entry.sampleCount),
  });
  postSoundCommand(state, { type: "sound-play", handle, soundId: id, looping: !!looping });
  return handle;
}

function soundPause(state, handle) {
  const playback = state.soundPlaybacks.get(handle | 0);
  if (!playback) return;
  playback.paused = true;
  postSoundCommand(state, { type: "sound-pause", handle: playback.handle });
}

function soundResume(state, handle) {
  const playback = state.soundPlaybacks.get(handle | 0);
  if (!playback) return;
  playback.paused = false;
  postSoundCommand(state, { type: "sound-resume", handle: playback.handle });
}

function soundStop(state, handle) {
  const key = handle | 0;
  if (!state.soundPlaybacks.delete(key)) return;
  postSoundCommand(state, { type: "sound-stop", handle: key });
}

function soundPositionUs(state, handle) {
  const playback = state.soundPlaybacks.get(handle | 0);
  if (!playback) return -1n;
  return BigInt(playback.positionSamples) * 1000000n / BigInt(SAMPLE_RATE);
}

function onSoundReport(state, report) {
  if (Array.isArray(report.playbacks)) {
    for (const item of report.playbacks) {
      const playback = state.soundPlaybacks.get(item.handle | 0);
      if (playback && Number.isInteger(item.positionSamples) && item.positionSamples >= 0) {
        playback.positionSamples = item.positionSamples;
      }
    }
  }
  if (Array.isArray(report.ended)) {
    for (const handle of report.ended) state.soundPlaybacks.delete(handle | 0);
  }
}

function mixScriptSounds(state, out) {
  const ended = new Set();
  for (let i = 0; i < out.length; i++) {
    let mixed = out[i];
    for (const playback of state.soundPlaybacks.values()) {
      if (playback.paused || ended.has(playback.handle)) continue;
      if (playback.cursor >= playback.samples.length) {
        if (playback.looping) {
          playback.cursor = 0;
        } else {
          ended.add(playback.handle);
          continue;
        }
      }
      mixed += playback.samples[playback.cursor] / 32768;
      playback.cursor += 1;
      if (playback.cursor >= playback.samples.length) {
        if (playback.looping) playback.cursor = 0;
        else ended.add(playback.handle);
      }
      playback.positionSamples = playback.cursor;
    }
    out[i] = Math.max(-1, Math.min(32767 / 32768, mixed));
  }
  for (const handle of ended) state.soundPlaybacks.delete(handle);
}

function soundPlaybackDetail(state) {
  return [...state.soundPlaybacks.values()].map((playback) => ({
    handle: playback.handle,
    soundId: playback.soundId,
    looping: playback.looping,
    paused: playback.paused,
    positionUs: soundPositionUs(state, playback.handle),
  }));
}

// ---------------------------------------------------------------------------
// Volume / mute (host-level master gain; the position clock keeps running mute)
// ---------------------------------------------------------------------------

function applyGain(state) {
  const gain = state.audio.gain;
  if (gain && gain.gain) gain.gain.value = state.muted ? 0 : state.volume / 100;
}

function setVolume(state, value) {
  const v = Math.round(Number(value));
  state.volume = Number.isFinite(v) ? Math.min(100, Math.max(0, v)) : 0;
  applyGain(state);
}

function setMuted(state, value) {
  state.muted = !!value;
  applyGain(state);
}

// ---------------------------------------------------------------------------
// Presentation: persistent views, RGB565 -> RGBA blit (lifecycle step 5)
// ---------------------------------------------------------------------------

function allocateViews(state) {
  state.fbView = new Uint16Array(state.memory.buffer, FB_PTR, FB_LEN / 2);
  if (state.canvas && state.ctx2d && typeof ImageData === "function") {
    state.imageData = new ImageData(FB_WIDTH, FB_HEIGHT);
    state.pixels = new Uint32Array(state.imageData.data.buffer);
  } else {
    // No canvas (Node tests, headless ABI runs): presentation is a no-op but
    // the dirty/consume protocol below is still maintained.
    state.imageData = null;
    state.pixels = null;
  }
}

/** Re-create the framebuffer view (and ImageData) ONLY when memory growth
 *  detached the old backing buffer; otherwise everything is allocated once. */
function ensureViews(state) {
  if (state.fbView && state.fbView.buffer === state.memory.buffer) return false;
  allocateViews(state);
  return true;
}

/** One RGB565 uint16 -> RGBA8888 uint32 conversion. Exported for tests.
 *  5/6-bit channels expand via bit replication. The ImageData buffer holds
 *  bytes R,G,B,A; a Uint32Array view of it on a little-endian platform is
 *  therefore 0xAABBGGRR (R in the low byte). */
export function rgb565ToRgba8888(rgb565) {
  const r5 = (rgb565 >> 11) & 0x1f;
  const g6 = (rgb565 >> 5) & 0x3f;
  const b5 = rgb565 & 0x1f;
  return (
    (0xff000000 |
      ((b5 << 3 | b5 >> 2) << 16) |
      ((g6 << 2 | g6 >> 4) << 8) |
      (r5 << 3 | r5 >> 2)) >>>
    0
  );
}

/** Tight blit into the reused ImageData; zero per-frame allocation. */
function blitFramebuffer(state) {
  ensureViews(state);
  const dst = state.pixels;
  if (!dst) return;
  const src = state.fbView;
  const n = src.length; // 19200 = 120*160
  for (let i = 0; i < n; i++) {
    const rgb = src[i];
    const r5 = (rgb >> 11) & 0x1f;
    const g6 = (rgb >> 5) & 0x3f;
    const b5 = rgb & 0x1f;
    dst[i] =
      0xff000000 |
      ((b5 << 3 | b5 >> 2) << 16) |
      ((g6 << 2 | g6 >> 4) << 8) |
      (r5 << 3 | r5 >> 2);
  }
  state.ctx2d.putImageData(state.imageData, 0, 0);
}

function setupCanvas(state, options, params) {
  const canvas = options.canvas;
  if (!canvas || typeof canvas.getContext !== "function") return;
  state.canvas = canvas;
  canvas.width = FB_WIDTH; // backing store is exactly 120x160; CSS scales it
  canvas.height = FB_HEIGHT;
  state.ctx2d = canvas.getContext("2d", { alpha: false });
  const scale = resolveScale(options, params);
  if (state.ctx2d && typeof canvas.style !== "undefined") {
    canvas.style.width = `${FB_WIDTH * scale}px`; // integer CSS scale, default 3x
    canvas.style.height = `${FB_HEIGHT * scale}px`;
    canvas.style.imageRendering = "pixelated";
  }
}

// ---------------------------------------------------------------------------
// Input: keyboard -> semantic button queue, flushed before each frame
// ---------------------------------------------------------------------------

const KEY_TO_BUTTON = {
  ArrowUp: BUTTON.Up,
  KeyW: BUTTON.Up,
  ArrowDown: BUTTON.Down,
  KeyS: BUTTON.Down,
  Enter: BUTTON.Ok,
  Space: BUTTON.Ok,
};

function attachInput(state) {
  if (typeof window === "undefined" || typeof window.addEventListener !== "function") return;
  // Multiple physical keys can name one semantic button (ArrowUp and W).
  // Count active source keys so releasing one alias cannot release the other.
  const downCodes = new Set();
  const heldCounts = [0, 0, 0];
  state.onKeyDown = (event) => {
    const button = KEY_TO_BUTTON[event.code];
    if (button === undefined) return;
    if (typeof event.preventDefault === "function") event.preventDefault(); // stop scrolling
    if (event.repeat || downCodes.has(event.code)) return;
    downCodes.add(event.code);
    heldCounts[button] += 1;
    if (heldCounts[button] === 1) state.inputQueue.push({ button, pressed: 1 });
  };
  state.onKeyUp = (event) => {
    const button = KEY_TO_BUTTON[event.code];
    if (button === undefined) return;
    if (typeof event.preventDefault === "function") event.preventDefault();
    if (!downCodes.delete(event.code)) return;
    heldCounts[button] -= 1;
    if (heldCounts[button] === 0) state.inputQueue.push({ button, pressed: 0 });
  };
  state.onBlur = () => {
    for (let button = BUTTON.Up; button <= BUTTON.Ok; button++) {
      if (heldCounts[button] > 0) state.inputQueue.push({ button, pressed: 0 });
      heldCounts[button] = 0;
    }
    downCodes.clear();
  };
  window.addEventListener("keydown", state.onKeyDown);
  window.addEventListener("keyup", state.onKeyUp);
  window.addEventListener("blur", state.onBlur);
}

function queueInput(state, button, pressed) {
  if (!Number.isInteger(button) || button < BUTTON.Up || button > BUTTON.Ok) {
    throw new TypeError(`queueInput: button must be 0 (Up), 1 (Down) or 2 (Ok); got ${button}`);
  }
  state.inputQueue.push({ button, pressed: pressed ? 1 : 0 });
}

// ---------------------------------------------------------------------------
// Frame lifecycle (steps 3-4): flush input -> passport_frame -> dirty blit
// ---------------------------------------------------------------------------

function tickOnce(state, nowUs) {
  if (state.disposed || !state.started) return null;
  // Step 3a: deliver queued input before the frame (ABI: delivered before the
  // next passport_frame).
  if (state.inputQueue.length > 0) {
    const queue = state.inputQueue;
    state.inputQueue = [];
    for (let i = 0; i < queue.length; i++) {
      state.exports.passport_input(queue[i].button, queue[i].pressed);
    }
  }
  // Step 3b: one app tick. now_us is i64 => BigInt at the boundary (ruling 4).
  const now = normalizeNowUs(state, nowUs);
  state.exports.passport_frame(now);
  state.frameCount += 1;
  state.lastNowUs = now;
  // Step 4: present + consume only when the app marked the frame dirty.
  let presented = false;
  if (state.exports.passport_frame_dirty() === 1) {
    blitFramebuffer(state);
    state.exports.passport_frame_consume();
    presented = true;
  }
  return { frameCount: state.frameCount, presented };
}

function startLoop(state) {
  if (state.running || state.disposed) return;
  state.running = true;
  if (typeof globalThis.requestAnimationFrame === "function") {
    const loop = () => {
      if (!state.running) return;
      tickOnce(state);
      state.rafId = globalThis.requestAnimationFrame(loop);
    };
    state.rafId = globalThis.requestAnimationFrame(loop);
  } else {
    // Node fallback; deterministic tests should call host.tick(nowUs) instead.
    state.intervalId = setInterval(() => {
      if (state.running) tickOnce(state);
    }, 16);
  }
}

function stopLoop(state) {
  state.running = false;
  if (state.rafId !== undefined && typeof globalThis.cancelAnimationFrame === "function") {
    globalThis.cancelAnimationFrame(state.rafId);
    state.rafId = undefined;
  }
  if (state.intervalId !== undefined) {
    clearInterval(state.intervalId);
    state.intervalId = undefined;
  }
}

function resumeAudio(state) {
  const ctx = state.audio.ctx;
  if (ctx && typeof ctx.resume === "function" && ctx.state === "suspended") {
    try {
      const p = ctx.resume();
      if (p && typeof p.then === "function") {
        p.catch(() => {});
      }
    } catch {
      // ignore: audio stays suspended until a later gesture
    }
  }
}

function dispose(state) {
  if (state.disposed) return;
  state.disposed = true;
  stopLoop(state);
  captureStop(state);
  if (state.hudTimer !== undefined) {
    clearInterval(state.hudTimer);
    state.hudTimer = undefined;
  }
  if (typeof window !== "undefined" && typeof window.removeEventListener === "function") {
    if (state.onKeyDown) window.removeEventListener("keydown", state.onKeyDown);
    if (state.onKeyUp) window.removeEventListener("keyup", state.onKeyUp);
    if (state.onBlur) window.removeEventListener("blur", state.onBlur);
  }
  const ctx = state.audio.ctx;
  if (ctx && typeof ctx.close === "function") {
    try {
      const p = ctx.close();
      if (p && typeof p.catch === "function") p.catch(() => {});
    } catch {
      // ignore
    }
  }
}

// ---------------------------------------------------------------------------
// Audio backend: AudioWorklet primary, ScriptProcessorNode fallback
// ---------------------------------------------------------------------------

async function setupAudio(state, options) {
  const audio = state.audio;
  let ctx = null;
  try {
    if (typeof options.audioContextFactory === "function") {
      // Injection seam (Node tests pass a fake context here).
      ctx = options.audioContextFactory({ sampleRate: SAMPLE_RATE });
    } else {
      const Ctx = globalThis.AudioContext || globalThis.webkitAudioContext;
      if (typeof Ctx === "function") ctx = new Ctx({ sampleRate: SAMPLE_RATE });
    }
  } catch (err) {
    audio.reason = `AudioContext construction failed: ${err}`;
    ctx = null;
  }
  if (!ctx) {
    audio.reason = audio.reason || "no AudioContext available (pass audioContextFactory in Node)";
    return;
  }
  audio.ctx = ctx;

  let gain = null;
  try {
    gain = typeof ctx.createGain === "function" ? ctx.createGain() : null;
  } catch (err) {
    audio.reason = `createGain failed: ${err}`;
  }
  if (!gain) {
    audio.reason = audio.reason || "AudioContext.createGain unavailable";
    return;
  }
  audio.gain = gain;
  applyGain(state);
  try {
    if (ctx.destination) gain.connect(ctx.destination);
  } catch (err) {
    audio.reason = `gain.connect failed: ${err}`;
  }
  audio.enabled = true;

  // Preferred transport: AudioWorklet on the real-time audio thread.
  const workletUrl = options.workletUrl || new URL("./sound-worklet.js", import.meta.url);
  if (
    ctx.audioWorklet &&
    typeof ctx.audioWorklet.addModule === "function" &&
    typeof globalThis.AudioWorkletNode === "function"
  ) {
    try {
      await ctx.audioWorklet.addModule(workletUrl);
      const node = new AudioWorkletNode(ctx, "passport-sound", {
        numberOfInputs: 0,
        numberOfOutputs: 1,
        outputChannelCount: [1],
      });
      node.port.onmessage = (event) => onSoundReport(state, event.data);
      node.connect(gain);
      audio.node = node;
      audio.kind = "worklet";
      const bankCopy = state.soundBank.bytes.slice(0);
      node.port.postMessage(
        { type: "sound-bank", bank: bankCopy, entries: state.soundBank.entries },
        [bankCopy],
      );
      return;
    } catch (err) {
      audio.workletError = String(err);
    }
  }
  // Fallback: ScriptProcessorNode (deprecated, runs on the main thread, so it
  // can jitter under load). Used ONLY when the engine has no usable
  // AudioWorklet — see README "Known limitations" for the full rationale.
  if (typeof ctx.createScriptProcessor === "function") {
    const sp = ctx.createScriptProcessor(SCRIPT_PROCESSOR_SAMPLES, 0, 1);
    sp.onaudioprocess = (event) => scriptProcessorPull(state, event);
    try {
      sp.connect(gain);
    } catch (err) {
      audio.reason = `scriptProcessor.connect failed: ${err}`;
    }
    audio.node = sp;
    audio.kind = "script";
    return;
  }
  // Context exists but no sound renderer is available.
  audio.kind = "none";
}

function scriptProcessorPull(state, event) {
  const out = event.outputBuffer.getChannelData(0);
  out.fill(0);
  mixScriptSounds(state, out);
}

// ---------------------------------------------------------------------------
// Microphone: permission, full-duplex PCM16 transport, bounded queue
// ---------------------------------------------------------------------------

function capturePush(state, value) {
  const capture = state.capture;
  if (capture.count === capture.ring.length) {
    capture.dropped += 1;
    return;
  }
  capture.ring[(capture.head + capture.count) % capture.ring.length] =
    value < 0 ? Math.max(-32768, Math.round(value * 32768))
      : Math.min(32767, Math.round(value * 32767));
  capture.count += 1;
}

function captureSamples(state, input) {
  const capture = state.capture;
  if (capture.status !== CAPTURE_STATUS.Recording) return;
  const sourceStep = capture.inputRate / SAMPLE_RATE;
  for (let i = 0; i < input.length; i++) {
    const current = input[i];
    const index = capture.sourceCount++;
    if (!capture.havePrevious) {
      capture.previous = current;
      capture.havePrevious = true;
      continue;
    }
    while (capture.nextOutputIndex <= index) {
      const fraction = capture.nextOutputIndex - (index - 1);
      capturePush(state, capture.previous + (current - capture.previous) * fraction);
      capture.nextOutputIndex += sourceStep;
    }
    capture.previous = current;
  }
}

function releaseCapture(state) {
  const capture = state.capture;
  capture.generation += 1;
  if (capture.source) capture.source.disconnect();
  if (capture.node) capture.node.disconnect();
  if (capture.stream) {
    for (const track of capture.stream.getTracks()) track.stop();
  }
  capture.source = null;
  capture.node = null;
  capture.stream = null;
  capture.head = 0;
  capture.count = 0;
}

function captureStop(state) {
  releaseCapture(state);
  state.capture.status = state.capture.available ? CAPTURE_STATUS.Idle : CAPTURE_STATUS.Unavailable;
}

function captureStart(state) {
  const capture = state.capture;
  if (!capture.available || !state.audio.ctx) return CAPTURE_STATUS.Unavailable;
  if (capture.status === CAPTURE_STATUS.Recording ||
      capture.status === CAPTURE_STATUS.Requesting) return capture.status;
  releaseCapture(state);
  capture.status = CAPTURE_STATUS.Requesting;
  capture.dropped = 0;
  capture.sourceCount = 0;
  capture.nextOutputIndex = 0;
  capture.havePrevious = false;
  capture.previous = 0;
  capture.error = null;
  const generation = capture.generation;
  const ctx = state.audio.ctx;
  (async () => {
    let stream = null;
    try {
      stream = await capture.mediaDevices.getUserMedia({
        audio: { channelCount: 1, sampleRate: { ideal: SAMPLE_RATE },
          echoCancellation: false, noiseSuppression: false, autoGainControl: false },
      });
      if (generation !== capture.generation || state.disposed) {
        for (const track of stream.getTracks()) track.stop();
        return;
      }
      capture.stream = stream;
      const source = ctx.createMediaStreamSource(stream);
      capture.source = source;
      let node;
      if (state.audio.kind === "worklet" && typeof globalThis.AudioWorkletNode === "function") {
        node = new AudioWorkletNode(ctx, "passport-microphone", {
          numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [1],
        });
        node.port.onmessage = (event) => captureSamples(state, event.data);
      } else if (typeof ctx.createScriptProcessor === "function") {
        node = ctx.createScriptProcessor(CAPTURE_SAMPLES, 1, 1);
        node.onaudioprocess = (event) => {
          event.outputBuffer.getChannelData(0).fill(0);
          captureSamples(state, event.inputBuffer.getChannelData(0));
        };
      } else {
        throw new Error("microphone capture needs AudioWorklet or ScriptProcessor");
      }
      capture.inputRate = ctx.sampleRate;
      if (!Number.isFinite(capture.inputRate) || capture.inputRate <= 0) {
        throw new Error(`invalid microphone AudioContext sample rate: ${capture.inputRate}`);
      }
      capture.node = node;
      source.connect(node);
      node.connect(ctx.destination); // capture processor outputs silence
      await ctx.resume();
      if (generation !== capture.generation || state.disposed) return;
      capture.status = CAPTURE_STATUS.Recording;
    } catch (err) {
      if (generation !== capture.generation || state.disposed) return;
      capture.error = String(err);
      console.error("[passport-host] microphone capture failed:", err);
      releaseCapture(state);
      capture.status = err?.name === "NotAllowedError" || err?.name === "SecurityError"
        ? CAPTURE_STATUS.Denied : CAPTURE_STATUS.Failed;
    }
  })();
  return CAPTURE_STATUS.Requesting;
}

function captureRead(state, maxSamples) {
  if (!Number.isInteger(maxSamples) || maxSamples < 0 || maxSamples > CAPTURE_SAMPLES) {
    throw new RangeError(`capture read limit must be 0..${CAPTURE_SAMPLES}`);
  }
  const capture = state.capture;
  if (capture.status !== CAPTURE_STATUS.Recording) {
    throw new Error(`capture read requires recording, status=${capture.status}`);
  }
  const count = Math.min(capture.count, maxSamples);
  const view = new DataView(state.memory.buffer);
  for (let i = 0; i < count; i++) {
    view.setInt16(CAPTURE_PTR + i * 2, capture.ring[capture.head], true);
    capture.head = (capture.head + 1) % capture.ring.length;
  }
  capture.count -= count;
  return count;
}

// ---------------------------------------------------------------------------
// Host-facts HUD (~4x/s)
// ---------------------------------------------------------------------------

function setupHud(state) {
  if (typeof document === "undefined" || typeof document.getElementById !== "function") return;
  const byId = (id) => document.getElementById(id);
  state.hud = {
    battery: byId("passport-battery"),
    sounds: byId("passport-sounds"),
    volume: byId("passport-volume"),
    mute: byId("passport-mute"),
    fps: byId("passport-fps"),
    status: byId("passport-status"),
  };
  state.hudTimer = setInterval(() => updateHud(state), HUD_INTERVAL_MS);
}

function updateHud(state) {
  if (!state.hud) return;
  const nowMs = Date.now();
  const dtSec = (nowMs - state.hudLast) / 1000;
  if (state.hud.fps && dtSec > 0) {
    state.hud.fps.textContent = String(Math.round((state.frameCount - state.hudLastFrame) / dtSec));
  }
  state.hudLast = nowMs;
  state.hudLastFrame = state.frameCount;
  if (state.hud.battery) {
    state.hud.battery.textContent = state.batteryPercent < 0 ? "n/a" : `${state.batteryPercent}%`;
  }
  if (state.hud.sounds) state.hud.sounds.textContent = `${state.soundPlaybacks.size} active`;
  if (state.hud.volume) state.hud.volume.textContent = String(state.volume);
  if (state.hud.mute) state.hud.mute.textContent = state.muted ? "on" : "off";
}

function setStatusText(state, text) {
  if (state.hud && state.hud.status) state.hud.status.textContent = text;
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

/**
 * Create and boot a passport wasm host.
 *
 * @param {object} [options]
 * @param {ArrayBuffer|TypedArray} [options.wasmBytes] - app wasm bytes
 *   (Node/tests). Mutually exclusive with wasmUrl/fetch.
 * @param {string|URL} [options.wasmUrl] - URL to fetch app.wasm from.
 *   Defaults to `new URL("app.wasm", import.meta.url)` (bundle dir contract:
 *   the page fetches app.wasm relative to the host module / page URL).
 * @param {string|URL} [options.fetch] - alias for wasmUrl.
 * @param {string|URL} [options.soundBankUrl] - APSB v1 bank URL. Defaults to
 *   a sibling sounds.bank for bundled apps.
 * @param {ArrayBuffer|TypedArray} [options.soundBankBytes] - inline APSB v1
 *   bank for embedded callers and tests.
 * @param {HTMLCanvasElement} [options.canvas] - presentation target; omitted
 *   (or Node) => presentation disabled, dirty/consume protocol still runs.
 * @param {(hint: {sampleRate: number}) => AudioContextLike} [options.audioContextFactory]
 *   - injection seam for tests; default constructs globalThis.AudioContext at
 *   16000 Hz. Omit in Node to run audio-less.
 * @param {MediaDevices} [options.mediaDevices] - microphone permission seam;
 *   defaults to navigator.mediaDevices when available.
 * @param {string|URL} [options.workletUrl] - sound-worklet.js URL; defaults to a
 *   sibling of this module.
 * @param {object} [options.imports] - `{ passport: { host_x: fn } }` per-key
 *   overrides merged over the default import implementations.
 * @param {() => bigint} [options.nowUs] - frame clock; default
 *   BigInt(Math.round(performance.now() * 1000)).
 * @param {number} [options.batteryPercent] - fixture override (URL ?battery=
 *   otherwise); default 82, -1 disables.
 * @param {number} [options.volume] - initial master volume 0..100 (default 100).
 * @param {boolean} [options.muted] - initial mute (default false).
 * @param {number} [options.scale] - CSS integer scale (URL ?scale= otherwise;
 *   default 3).
 * @returns {Promise<PassportHost>} see buildHostApi for the surface.
 */
export async function createHost(options = {}) {
  requireLittleEndian(); // ABI v0 boot check
  if (options.nowUs !== undefined && typeof options.nowUs !== "function") {
    throw new TypeError("createHost: options.nowUs must be a function returning BigInt microseconds");
  }
  const params = readUrlParams();
  const soundBank = parseSoundBank(await loadSoundBankBytes(options));

  const state = {
    options,
    nowUs: options.nowUs || defaultNowUs,
    batteryPercent: resolveBatteryPercent(options, params),
    volume: clampVolume(options.volume),
    muted: !!options.muted,
    memory: null,
    exports: null,
    started: false,
    disposed: false,
    fbView: null,
    imageData: null,
    pixels: null,
    canvas: null,
    ctx2d: null,
    inputQueue: [],
    frameCount: 0,
    lastNowUs: null,
    soundBank,
    soundPlaybacks: new Map(),
    nextSoundHandle: 1,
    audio: {
      enabled: false,
      kind: "none", // "worklet" | "script" | "none"
      ctx: null,
      gain: null,
      node: null,
      workletError: null,
      reason: "",
    },
    capture: {
      mediaDevices: options.mediaDevices ||
        (typeof navigator !== "undefined" ? navigator.mediaDevices : null),
      available: false,
      status: CAPTURE_STATUS.Unavailable,
      generation: 0,
      stream: null,
      source: null,
      node: null,
      ring: new Int16Array(CAPTURE_RING_SAMPLES),
      head: 0,
      count: 0,
      dropped: 0,
      inputRate: 0,
      sourceCount: 0,
      nextOutputIndex: 0,
      previous: 0,
      havePrevious: false,
      error: null,
    },
    hud: null,
    hudTimer: undefined,
    hudLast: Date.now(),
    hudLastFrame: 0,
    running: false,
    rafId: undefined,
    intervalId: undefined,
    onKeyDown: null,
    onKeyUp: null,
    onBlur: null,
  };

  // Host-side implementations of the internal "passport" import module.
  const imports = {
    passport: {
      host_battery_percent: () => state.batteryPercent,
      host_set_volume: (value) => setVolume(state, value),
      host_set_muted: (value) => setMuted(state, value),
      host_sound_play: (soundId, looping) => soundPlay(state, soundId, looping),
      host_sound_pause: (handle) => soundPause(state, handle),
      host_sound_resume: (handle) => soundResume(state, handle),
      host_sound_stop: (handle) => soundStop(state, handle),
      host_sound_position_us: (handle) => soundPositionUs(state, handle),
      host_capture_start: () => captureStart(state),
      host_capture_status: () => state.capture.status,
      host_capture_stop: () => captureStop(state),
      host_capture_read: (maxSamples) => captureRead(state, maxSamples),
      host_capture_dropped: () => Math.min(state.capture.dropped, 2147483647),
    },
  };
  const overrides = options.imports && options.imports.passport;
  if (overrides) {
    for (const key of Object.keys(overrides)) {
      if (typeof overrides[key] === "function") imports.passport[key] = overrides[key];
    }
  }

  // Lifecycle step 1: instantiate the application against the Host ABI.
  const bytes = await loadWasmBytes(options);
  const { instance } = await WebAssembly.instantiate(bytes, imports);
  const appExports = instance.exports;
  const missing = REQUIRED_EXPORTS.filter((name) => typeof appExports[name] !== "function");
  if (missing.length > 0) {
    throw new Error(`passport-host: app.wasm missing required exports: ${missing.join(", ")}`);
  }
  if (!appExports.memory || !(appExports.memory.buffer instanceof ArrayBuffer)) {
    throw new Error('passport-host: app.wasm must export its linear memory as "memory"');
  }
  state.memory = appExports.memory;
  state.exports = appExports;

  setupCanvas(state, options, params);
  attachInput(state);
  setupHud(state);
  await setupAudio(state, options);
  state.capture.available =
    typeof state.capture.mediaDevices?.getUserMedia === "function" &&
    !!state.audio.ctx &&
    (state.audio.kind === "worklet" ||
      typeof state.audio.ctx.createScriptProcessor === "function");
  state.capture.status = state.capture.available ? CAPTURE_STATUS.Idle : CAPTURE_STATUS.Unavailable;

  // Lifecycle step 2: _start() exactly once; app main initializes and RETURNS.
  appExports._start();
  state.started = true;

  // Post-init ABI sanity: the framebuffer must sit exactly where ABI v0 says.
  const fbPtr = appExports.passport_fb_ptr() >>> 0;
  const fbLen = appExports.passport_fb_len() >>> 0;
  if (fbPtr !== FB_PTR || fbLen !== FB_LEN) {
    throw new Error(
      `passport-host: framebuffer mismatch: app reports ptr=${fbPtr} len=${fbLen}; ` +
        `ABI v0 requires ptr=${FB_PTR} len=${FB_LEN} (check heap-start-address and link.wasm.exports)`,
    );
  }
  allocateViews(state);
  updateHud(state);

  return buildHostApi(state, imports, appExports);
}

/**
 * The host object returned by createHost (mirrored at window.__passportHost
 * in the browser auto-boot).
 * @typedef {object} PassportHost
 * @property {() => number} frameCount - frames ticked since boot.
 * @property {bigint|null} lastNowUs - now_us of the last passport_frame.
 * @property {() => number} inputQueueLength - queued, not-yet-flushed events.
 * @property {() => number} batteryPercent - fixture value (-1 = unavailable).
 * @property {() => number} volume - master volume 0..100.
 * @property {() => boolean} muted
 * @property {(v: number) => void} setVolume
 * @property {(b: boolean|number) => void} setMuted
 * @property {Array<object>} soundPlaybacks - live playback facts.
 * @property {(button: number, pressed: boolean|number) => void} queueInput
 * @property {(nowUs?: bigint|number) => {frameCount: number, presented: boolean}|null} tick
 *   - run exactly one frame cycle manually (tests drive frames without rAF).
 * @property {() => void} start - rAF loop (setInterval fallback in Node).
 * @property {() => void} stop
 * @property {() => void} resumeAudio - called on first user gesture in browser.
 * @property {() => Uint16Array} getFramebufferView - 19200-entry RGB565 view
 *   (re-created transparently after wasm memory growth).
 * @property {() => void} dispose
 * @property {object} imports - the "passport" import object used.
 * @property {object} exports - the app's wasm exports.
 * @property {WebAssembly.Memory} memory
 * @property {object} audio - { enabled, kind, ctx, gain, node,
 *   workletError, reason }.
 */
function buildHostApi(state, imports, appExports) {
  return {
    get imports() {
      return imports;
    },
    get exports() {
      return appExports;
    },
    get memory() {
      return state.memory;
    },
    get audio() {
      return state.audio;
    },
    get capture() {
      return state.capture;
    },
    get frameCount() {
      return state.frameCount;
    },
    get lastNowUs() {
      return state.lastNowUs;
    },
    get inputQueueLength() {
      return state.inputQueue.length;
    },
    get batteryPercent() {
      return state.batteryPercent;
    },
    get volume() {
      return state.volume;
    },
    get muted() {
      return state.muted;
    },
    setVolume: (value) => setVolume(state, value),
    setMuted: (value) => setMuted(state, value),
    get soundPlaybacks() {
      return soundPlaybackDetail(state);
    },
    queueInput: (button, pressed) => queueInput(state, button, pressed),
    tick: (nowUs) => tickOnce(state, nowUs),
    start: () => startLoop(state),
    stop: () => stopLoop(state),
    resumeAudio: () => resumeAudio(state),
    getFramebufferView: () => {
      ensureViews(state);
      return state.fbView;
    },
    dispose: () => dispose(state),
  };
}

// ---------------------------------------------------------------------------
// Browser auto-boot (runs only when a DOM root exists; index.html loads this
// module). Node never executes this branch.
// ---------------------------------------------------------------------------

async function autoBootFromDom() {
  if (typeof document === "undefined" || typeof document.getElementById !== "function") return;
  const canvas = document.getElementById("passport-canvas");
  if (!canvas) {
    console.warn("[passport-host] #passport-canvas not found; auto-boot skipped");
    return;
  }
  try {
    const host = await createHost({ canvas });
    globalThis.__passportHost = host;
    // Write the status line through the DOM directly, like the catch handler
    // below: setStatusText expects the INTERNAL state object, but only the
    // public host object exists here (it exposes no hud) — passing it made
    // this call a silent no-op and left the page at "booting…" forever.
    const statusEl = document.getElementById("passport-status");
    if (statusEl) {
      statusEl.textContent = host.audio.enabled
        ? `running (audio: ${host.audio.kind})`
        : `running (${host.audio.reason || "audio unavailable"})`;
    }
    const resume = () => host.resumeAudio(); // unlock the AudioContext on first gesture
    window.addEventListener("keydown", resume);
    window.addEventListener("pointerdown", resume);
    host.start();
  } catch (err) {
    console.error("[passport-host] boot failed:", err);
    if (typeof document !== "undefined") {
      const el = document.getElementById("passport-status");
      if (el) el.textContent = `boot failed: ${err && err.message ? err.message : err}`;
    }
  }
}

if (typeof document !== "undefined") {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", autoBootFromDom, { once: true });
  } else {
    autoBootFromDom();
  }
}
