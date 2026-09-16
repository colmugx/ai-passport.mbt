/**
 * passport-host.js — application-agnostic WebAssembly host backend for the
 * AI Passport SDK. Implements the FROZEN ABI v0 contract (framebuffer
 * 120x160 RGB565 LE at byte offset 4096, length 38400; PCM staging buffer at
 * 42496; normalized PCM16 LE mono at 16000 Hz).
 *
 * Host responsibilities (the frozen JS/app split):
 *   - instantiate app.wasm, provide the "passport" imports, call _start() once
 *   - per frame: flush queued input events, call passport_frame(now_us:BigInt),
 *     blit the 120x160 RGB565 LE framebuffer when dirty, then consume
 *   - normalized PCM16 LE mono 16000 Hz playback (AudioWorklet primary,
 *     ScriptProcessorNode fallback), master volume/mute gain, best-effort
 *     playback position
 *   - optional PCM ASSET mode (createHost options pcmAssetUrl/pcmAssetBytes +
 *     pcmLoop): the host itself fetches an already-normalized .pcm artifact
 *     and streams it through the SAME decode/queue/transport path as
 *     host_pcm_write, in bounded chunks with sample-exact looping. The two
 *     producer modes are explicitly exclusive (see resolvePcmAssetConfig).
 *   - keyboard -> semantic buttons (Up/Down/Ok), host-facts HUD
 *
 * There is NO application logic here: nothing knows about any specific app,
 * sprites, BPM, or asset formats. Authored MP3/WAV files are decoded by an
 * asset compiler outside this file; this host only ever sees normalized PCM.
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
/** PCM staging buffer offset (app-internal; the host only READS ranges the
 *  app explicitly hands to host_pcm_write — it never addresses this region). */
export const PCM_STAGING_PTR = 0xa600; // 42496
export const PCM_STAGING_LEN = 16384; // 8192 PCM16 LE samples
/** Normalized PCM stream format: PCM16 LE mono at this rate. */
export const SAMPLE_RATE = 16000;
/** App heap start; [0, 65536) is ABI-reserved and the host never writes it. */
export const HEAP_START = 65536;

const TARGET_BUFFERED_SAMPLES = 3200; // ~200 ms at 16 kHz kept in the worklet ring
const MAX_PENDING_SAMPLES = 160000; // ~10 s backstop when nothing drains the queue
const SCRIPT_PROCESSOR_SAMPLES = 4096; // ScriptProcessor pull size (fallback transport)
const ASSET_CHUNK_SAMPLES = 3200; // PCM asset decode granularity (~200 ms at 16 kHz)
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

/** ABI v0 boot check: framebuffer and PCM are little-endian; reject BE hosts. */
function requireLittleEndian() {
  const probe = new Uint32Array(new Uint8Array([0x01, 0x00, 0x00, 0x00]).buffer);
  if (probe[0] !== 1) {
    throw new Error(
      "passport-host: big-endian platform detected. ABI v0 stores the framebuffer " +
        "(RGB565 uint16) and PCM (PCM16 LE) little-endian; refusing to run rather " +
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

// ---------------------------------------------------------------------------
// PCM asset configuration (host configuration, never application semantics)
// ---------------------------------------------------------------------------

/** Validate and normalize the PCM asset options. Returns null when the host is
 *  NOT configured for asset playback (the default streamed-PCM mode), or
 *  { source: "url"|"bytes", url, bytes, loop } when it is. The two producer
 *  modes are explicitly exclusive: an app that imports host_pcm_write cannot
 *  boot on an asset-configured host (checked in createHost against the module
 *  import table), and the streamed-PCM test seam refuses to run. */
function resolvePcmAssetConfig(options) {
  const hasUrl = options.pcmAssetUrl !== undefined;
  const hasBytes = options.pcmAssetBytes !== undefined;
  const loop = !!options.pcmLoop;
  if (hasUrl && hasBytes) {
    throw new TypeError("createHost: pcmAssetUrl and pcmAssetBytes are mutually exclusive; pass exactly one");
  }
  if (!hasUrl && !hasBytes) {
    if (loop) {
      throw new TypeError("createHost: pcmLoop requires pcmAssetUrl or pcmAssetBytes");
    }
    return null;
  }
  if (hasUrl) {
    const url = options.pcmAssetUrl;
    if (typeof url !== "string" && !(url instanceof URL)) {
      throw new TypeError("createHost: options.pcmAssetUrl must be a string or URL of a normalized .pcm artifact");
    }
    return { source: "url", url: String(url), bytes: null, loop };
  }
  const bytes = options.pcmAssetBytes;
  if (!(bytes instanceof ArrayBuffer) && !ArrayBuffer.isView(bytes)) {
    throw new TypeError("createHost: options.pcmAssetBytes must be an ArrayBuffer or TypedArray of PCM16 LE mono 16000 Hz");
  }
  return { source: "bytes", url: null, bytes, loop };
}

/** Exact-copy a TypedArray input into its own ArrayBuffer (done once, at
 *  load); ArrayBuffer input is authoritative already. */
function normalizeAssetBytes(input) {
  if (input instanceof ArrayBuffer) return input;
  const out = new ArrayBuffer(input.byteLength);
  new Uint8Array(out).set(new Uint8Array(input.buffer, input.byteOffset, input.byteLength));
  return out;
}

// ---------------------------------------------------------------------------
// Normalized PCM path: decode (PCM16 LE -> Float32), queue, transport, position
// ---------------------------------------------------------------------------

/** Synchronous copy-out + decode: PCM16 LE -> Float32 in [-1, 1). Handles an
 *  odd (misaligned) byte offset via DataView; even offsets use Int16Array,
 *  which is safe because the boot check proved the platform is little-endian. */
function decodePcm16Le(buffer, byteOffset, sampleCount) {
  const out = new Float32Array(sampleCount);
  if ((byteOffset & 1) === 0) {
    const view = new Int16Array(buffer, byteOffset, sampleCount);
    for (let i = 0; i < sampleCount; i++) out[i] = view[i] / 32768;
  } else {
    const dv = new DataView(buffer, byteOffset, sampleCount * 2);
    for (let i = 0; i < sampleCount; i++) out[i] = dv.getInt16(i * 2, true) / 32768;
  }
  return out;
}

/** passport import host_pcm_write(ptr, samples): copy out synchronously and
 *  queue; NEVER blocks the wasm call. Refused on an asset-configured host —
 *  but that is already prevented at boot (createHost rejects a module that
 *  imports host_pcm_write while an asset is configured); this guard covers
 *  import overrides only. */
function onPcmWrite(state, ptr, samples) {
  if (state.asset) {
    throw new Error(
      "passport host_pcm_write: this host is configured for PCM asset playback " +
        "(pcmAssetUrl/pcmAssetBytes); streamed PCM and asset playback are mutually exclusive",
    );
  }
  state.pcmStats.calls += 1;
  const count = samples | 0;
  if (count <= 0) return;
  const buffer = state.memory.buffer;
  const byteLength = count * 2;
  if (ptr < 0 || ptr + byteLength > buffer.byteLength) {
    throw new RangeError(
      `passport host_pcm_write: range [${ptr}, ${ptr + byteLength}) is outside wasm memory (${buffer.byteLength} bytes)`,
    );
  }
  const chunk = decodePcm16Le(buffer, ptr, count);
  state.pcmStats.bytesReceived += byteLength;
  enqueueDecoded(state, chunk);
}

/** Shared sink for host_pcm_write, feedNormalizedPcm and the PCM asset
 *  refiller (the SAME normalized-PCM path). Drop-oldest backstop only matters
 *  when no audio backend drains the queue (e.g. Node without an injected fake
 *  context). */
function enqueueDecoded(state, chunk) {
  state.pending.push(chunk);
  state.pendingSamples += chunk.length;
  if (state.pendingSamples > state.peakPendingSamples) state.peakPendingSamples = state.pendingSamples;
  while (state.pendingSamples > MAX_PENDING_SAMPLES) {
    const oldest = state.pending.shift();
    state.pendingSamples -= oldest.length;
    state.pcmStats.droppedSamples += oldest.length;
  }
  pump(state);
}

/** Forward decoded chunks to the worklet ring, keeping ~200 ms buffered there.
 *  Whole chunks only, so scheduling stays gapless. NOTE: capture the length
 *  BEFORE postMessage — the transfer list detaches chunk.buffer, and a
 *  TypedArray over a detached buffer reports length 0 (which would freeze
 *  estimatedFill at its last value and, with the asset refiller, spin the
 *  pump/refill loop forever). */
function pump(state) {
  if (state.audio.kind !== "worklet" || !state.audio.node) return; // SP mode pulls itself
  while (state.pending.length > 0 && state.estimatedFill < TARGET_BUFFERED_SAMPLES) {
    const chunk = state.pending.shift();
    const len = chunk.length; // pre-transfer length
    state.pendingSamples -= len;
    state.audio.node.port.postMessage({ type: "pcm", data: chunk }, [chunk.buffer]);
    state.estimatedFill += len;
  }
}

/** Message from pcm-worklet.js: { type:"report", filled, consumed, underruns,
 *  dropped }. Also usable as a test seam to simulate worklet consumption. */
function onAudioReport(state, report) {
  if (!report || typeof report !== "object") return;
  const ctx = state.audio.ctx;
  if (typeof report.consumed === "number" && ctx) {
    state.posSnapshot = { samples: report.consumed, ctxTime: ctx.currentTime };
  }
  if (typeof report.filled === "number") state.estimatedFill = report.filled;
  if (typeof report.underruns === "number") state.audio.underruns = report.underruns;
  if (typeof report.dropped === "number") state.audio.dropped = report.dropped;
  serviceAudio(state);
}

/** Best-effort playback position in microseconds (BigInt, i64 at the ABI).
 *  Formula: position_us = (consumedSamples + (ctx.currentTime -
 *  snapshotCtxTime) * 16000) * 1e6/16000, where the snapshot {samples,
 *  ctxTime} comes from the most recent worklet consumption report (or
 *  ScriptProcessor pull). Returns 0n before any playback and whenever no
 *  audio backend exists. The clock runs on consumption, not on gain, so
 *  muting does not stop it. */
function playbackPosUs(state) {
  if (!state.audio.enabled) return 0n;
  const snapshot = state.posSnapshot;
  if (!snapshot) return 0n;
  const ctx = state.audio.ctx;
  const elapsedSamples = Math.max(0, ctx.currentTime - snapshot.ctxTime) * SAMPLE_RATE;
  return BigInt(Math.round((snapshot.samples + elapsedSamples) * (1e6 / SAMPLE_RATE)));
}

/** Test entry: inject normalized PCM16 LE through the SAME decode+queue path
 *  as host_pcm_write. Does not touch pcmStats (which counts the wasm import).
 *  Refused on an asset-configured host (the two producer modes are exclusive). */
function feedNormalizedPcm(state, input) {
  if (state.asset) {
    throw new TypeError(
      "feedNormalizedPcm: this host is configured for PCM asset playback " +
        "(pcmAssetUrl/pcmAssetBytes); streamed PCM and asset playback are mutually exclusive",
    );
  }
  let view;
  if (input instanceof Int16Array) {
    view = input;
  } else if (input instanceof ArrayBuffer) {
    if (input.byteLength % 2 !== 0) {
      throw new TypeError("feedNormalizedPcm: ArrayBuffer byte length must be even (PCM16)");
    }
    view = new Int16Array(input);
  } else {
    throw new TypeError("feedNormalizedPcm: expected Int16Array or ArrayBuffer of PCM16 LE mono 16000 Hz");
  }
  const chunk = new Float32Array(view.length);
  for (let i = 0; i < view.length; i++) chunk[i] = view[i] / 32768;
  enqueueDecoded(state, chunk);
}

// ---------------------------------------------------------------------------
// PCM asset playback: fetch raw .pcm bytes once, then bounded refill
// ---------------------------------------------------------------------------

/** Load the configured asset WITHOUT blocking app frames: createHost kicks
 *  this off and resolves state.asset.ready when the raw bytes are resident
 *  (or records the failure and keeps the host alive). The raw ArrayBuffer is
 *  the authoritative artifact and stays resident; NO whole-track Float32 copy
 *  is ever created — decoding happens in bounded chunks (refillAsset). */
async function loadPcmAsset(state) {
  const asset = state.asset;
  try {
    let buffer;
    if (asset.source === "bytes") {
      buffer = normalizeAssetBytes(asset.bytesInput);
    } else {
      if (typeof fetch !== "function") {
        throw new Error(`passport-host: cannot fetch PCM asset at ${asset.url}: fetch() unavailable here; pass options.pcmAssetBytes`);
      }
      const response = await fetch(asset.url);
      if (!response.ok) {
        throw new Error(`passport-host: failed to fetch PCM asset at ${asset.url}: HTTP ${response.status}`);
      }
      buffer = await response.arrayBuffer();
    }
    if (buffer.byteLength === 0) {
      throw new Error(`passport-host: PCM asset at ${asset.source === "url" ? asset.url : "pcmAssetBytes"} is empty (0 samples)`);
    }
    if (buffer.byteLength % 2 !== 0) {
      throw new Error(
        `passport-host: PCM asset byte length ${buffer.byteLength} is not even; the accepted format is strictly PCM16 LE mono 16000 Hz (no header, no MP3/WAV)`,
      );
    }
    if (state.disposed) return;
    asset.bytes = buffer;
    asset.samples = buffer.byteLength / 2;
    asset.loaded = true;
    serviceAudio(state);
    asset.resolveReady();
  } catch (err) {
    asset.error = String(err && err.message ? err.message : err);
    if (state.hud) setStatusText(state, `audio asset error: ${asset.error}`);
    asset.rejectReady(err instanceof Error ? err : new Error(asset.error));
  }
}

/** Decode the NEXT bounded chunk from the resident raw PCM artifact. A chunk
 *  never crosses the loop seam: when fewer than ASSET_CHUNK_SAMPLES remain,
 *  the chunk is short and the cursor wraps to sample 0 (loop) or hits EOF.
 *  Looping is therefore sample-exact: the stream is s[0..N-1] repeated, with
 *  no silence, padding, or duplicated sample at the boundary. */
function decodeNextAssetChunk(state) {
  const asset = state.asset;
  const count = Math.min(ASSET_CHUNK_SAMPLES, asset.samples - asset.cursor);
  const out = new Float32Array(count);
  const view = new Int16Array(asset.bytes, asset.cursor * 2, count); // even offset, LE platform (boot check)
  for (let i = 0; i < count; i++) out[i] = view[i] / 32768;
  asset.cursor += count;
  if (asset.cursor >= asset.samples) {
    if (asset.loop) {
      asset.cursor = 0;
      asset.decodeWraps += 1;
    } else {
      asset.eof = true; // non-loop: stop feeding after the last sample
    }
  }
  asset.chunksDecoded += 1;
  if (count > asset.maxChunkSamples) asset.maxChunkSamples = count;
  return out;
}

/** Pending-side refill budget. ScriptProcessor pulls up to 4096 samples
 *  synchronously out of `pending`, so in script mode keep two pull buffers
 *  queued; in worklet mode the ~200 ms pump target bounds everything. */
function assetPendingTarget(state) {
  return state.audio.kind === "script" ? SCRIPT_PROCESSOR_SAMPLES * 2 : TARGET_BUFFERED_SAMPLES;
}

/** Demand-driven refill: decode bounded chunks from the raw artifact only
 *  while the decoded queue is below the budget. Never touches the artifact
 *  bytes beyond the cursor, never decodes the whole track at once, and stops
 *  permanently at EOF in non-loop mode. */
function refillAsset(state) {
  const asset = state.asset;
  if (!asset || !asset.loaded || asset.eof) return;
  while (state.pendingSamples < assetPendingTarget(state)) {
    enqueueDecoded(state, decodeNextAssetChunk(state));
    if (asset.eof) break;
  }
}

/** Unified audio servicing: forward pending chunks toward the transport
 *  (pump), then top the queue up from the PCM asset if one is configured.
 *  Called after every consumption report, ScriptProcessor pull, resume, and
 *  asset load. */
function serviceAudio(state) {
  if (state.disposed) return;
  pump(state);
  refillAsset(state);
}

/** Host-side asset facts snapshot for tooling/tests (never a wasm import). */
function assetDetail(state) {
  if (!state.asset) {
    return {
      configured: false,
      source: null,
      url: null,
      loaded: false,
      error: null,
      samples: 0,
      byteLength: 0,
      durationUs: 0n,
      looping: false,
      cursor: 0,
      eof: false,
      chunkSamples: ASSET_CHUNK_SAMPLES,
      chunksDecoded: 0,
      maxChunkSamples: 0,
      pendingSamples: state.pendingSamples,
      peakPendingSamples: state.peakPendingSamples,
      loops: 0,
    };
  }
  const asset = state.asset;
  const consumed = state.posSnapshot ? state.posSnapshot.samples : 0;
  return {
    configured: true,
    source: asset.source,
    url: asset.url,
    loaded: asset.loaded,
    error: asset.error,
    samples: asset.loaded ? asset.samples : 0,
    byteLength: asset.bytes ? asset.bytes.byteLength : 0,
    durationUs: asset.loaded ? assetDurationUsValue(asset.samples) : 0n,
    looping: asset.loop,
    cursor: asset.cursor,
    eof: asset.eof,
    chunkSamples: ASSET_CHUNK_SAMPLES,
    chunksDecoded: asset.chunksDecoded,
    maxChunkSamples: asset.maxChunkSamples,
    pendingSamples: state.pendingSamples,
    peakPendingSamples: state.peakPendingSamples,
    loops: asset.loaded ? Math.floor(consumed / asset.samples) : 0,
  };
}

function assetDurationUsValue(samples) {
  return BigInt(Math.round((samples * 1e6) / SAMPLE_RATE));
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
  state.onKeyDown = (event) => {
    const button = KEY_TO_BUTTON[event.code];
    if (button === undefined) return;
    if (typeof event.preventDefault === "function") event.preventDefault(); // stop scrolling
    if (event.repeat) return; // ignore auto-repeat
    state.inputQueue.push({ button, pressed: 1 });
  };
  state.onKeyUp = (event) => {
    const button = KEY_TO_BUTTON[event.code];
    if (button === undefined) return;
    if (typeof event.preventDefault === "function") event.preventDefault();
    state.inputQueue.push({ button, pressed: 0 });
  };
  window.addEventListener("keydown", state.onKeyDown);
  window.addEventListener("keyup", state.onKeyUp);
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
        p.then(() => serviceAudio(state)).catch(() => {});
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
  if (state.hudTimer !== undefined) {
    clearInterval(state.hudTimer);
    state.hudTimer = undefined;
  }
  if (typeof window !== "undefined" && typeof window.removeEventListener === "function") {
    if (state.onKeyDown) window.removeEventListener("keydown", state.onKeyDown);
    if (state.onKeyUp) window.removeEventListener("keyup", state.onKeyUp);
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
  const workletUrl = options.workletUrl || new URL("./pcm-worklet.js", import.meta.url);
  if (
    ctx.audioWorklet &&
    typeof ctx.audioWorklet.addModule === "function" &&
    typeof globalThis.AudioWorkletNode === "function"
  ) {
    try {
      await ctx.audioWorklet.addModule(workletUrl);
      const node = new AudioWorkletNode(ctx, "passport-pcm", {
        numberOfInputs: 0,
        numberOfOutputs: 1,
        outputChannelCount: [1],
      });
      node.port.onmessage = (event) => onAudioReport(state, event.data);
      node.connect(gain);
      audio.node = node;
      audio.kind = "worklet";
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
  // Context exists but nothing can pull: the queue drains only via
  // onAudioReport() (useful as a deterministic Node test seam).
  audio.kind = "none";
}

function scriptProcessorPull(state, event) {
  const out = event.outputBuffer.getChannelData(0);
  let i = 0;
  while (i < out.length && state.pending.length > 0) {
    const chunk = state.pending[0];
    const need = out.length - i;
    if (chunk.length <= need) {
      out.set(chunk, i);
      i += chunk.length;
      state.pending.shift();
      state.pendingSamples -= chunk.length;
      state.spConsumed += chunk.length;
    } else {
      out.set(chunk.subarray(0, need), i);
      i += need;
      state.pending[0] = chunk.subarray(need);
      state.pendingSamples -= need;
      state.spConsumed += need;
    }
  }
  while (i < out.length) out[i++] = 0; // underrun: silence
  const ctx = state.audio.ctx;
  if (ctx) state.posSnapshot = { samples: state.spConsumed, ctxTime: ctx.currentTime };
  serviceAudio(state); // pull drained the queue: top it up from the asset, if any
}

// ---------------------------------------------------------------------------
// Host-facts HUD (~4x/s)
// ---------------------------------------------------------------------------

function setupHud(state) {
  if (typeof document === "undefined" || typeof document.getElementById !== "function") return;
  const byId = (id) => document.getElementById(id);
  state.hud = {
    battery: byId("passport-battery"),
    pos: byId("passport-pos"),
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
  if (state.hud.pos) state.hud.pos.textContent = `${(Number(playbackPosUs(state)) / 1e6).toFixed(3)} s`;
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
 * @param {HTMLCanvasElement} [options.canvas] - presentation target; omitted
 *   (or Node) => presentation disabled, dirty/consume protocol still runs.
 * @param {(hint: {sampleRate: number}) => AudioContextLike} [options.audioContextFactory]
 *   - injection seam for tests; default constructs globalThis.AudioContext at
 *   16000 Hz. Omit in Node to run audio-less.
 * @param {string|URL} [options.workletUrl] - pcm-worklet.js URL; defaults to a
 *   sibling of this module.
 * @param {string|URL} [options.pcmAssetUrl] - URL of an ALREADY-NORMALIZED
 *   .pcm artifact (signed PCM16 LE mono 16000 Hz, headerless, even byte
 *   length). Configures PCM asset mode: the host fetches the raw bytes and
 *   streams them through the same audio transport in bounded chunks. The app
 *   must NOT import host_pcm_write (the two producer modes are exclusive and
 *   mixing them fails at boot). Fetching never blocks app frames.
 * @param {ArrayBuffer|TypedArray} [options.pcmAssetBytes] - inline variant of
 *   pcmAssetUrl (Node/tests, data: pages). Mutually exclusive with pcmAssetUrl.
 * @param {boolean} [options.pcmLoop] - loop the asset at the exact PCM sample
 *   boundary (default false: play to EOF, then stop feeding).
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
  const assetConfig = resolvePcmAssetConfig(options);

  let assetState = null;
  if (assetConfig) {
    let resolveReady;
    let rejectReady;
    const readyPromise = new Promise((resolve, reject) => {
      resolveReady = resolve;
      rejectReady = reject;
    });
    // Mark rejection handled at the source: pages that never await
    // waitForAudioAsset() must not trip unhandled-promise-rejection reporting.
    readyPromise.catch(() => {});
    assetState = {
      configured: true,
      source: assetConfig.source,
      url: assetConfig.source === "url" ? assetConfig.url : null,
      bytesInput: assetConfig.bytes,
      loop: assetConfig.loop,
      bytes: null,
      samples: 0,
      loaded: false,
      error: null,
      cursor: 0,
      eof: false,
      decodeWraps: 0,
      chunksDecoded: 0,
      maxChunkSamples: 0,
      readyPromise,
      resolveReady,
      rejectReady,
    };
  }

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
    pending: [],
    pendingSamples: 0,
    peakPendingSamples: 0,
    estimatedFill: 0,
    spConsumed: 0,
    posSnapshot: null,
    pcmStats: { bytesReceived: 0, calls: 0, droppedSamples: 0 },
    asset: assetState,
    audio: {
      enabled: false,
      kind: "none", // "worklet" | "script" | "none"
      ctx: null,
      gain: null,
      node: null,
      underruns: 0,
      dropped: 0,
      workletError: null,
      reason: "",
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
  };

  // Host-side implementations of the frozen "passport" import module.
  const imports = {
    passport: {
      host_battery_percent: () => state.batteryPercent,
      host_pcm_write: (ptr, samples) => onPcmWrite(state, ptr, samples),
      host_set_volume: (value) => setVolume(state, value),
      host_set_muted: (value) => setMuted(state, value),
      host_playback_pos_us: () => playbackPosUs(state),
    },
  };
  const overrides = options.imports && options.imports.passport;
  if (overrides) {
    for (const key of Object.keys(overrides)) {
      if (typeof overrides[key] === "function") imports.passport[key] = overrides[key];
    }
  }

  // Lifecycle step 1: compile, enforce producer-mode exclusivity, instantiate.
  // Compiling the Module first lets the host inspect the declared imports: an
  // app that imports passport.host_pcm_write is a streamed-PCM app and cannot
  // run on an asset-configured host — fail loudly at boot, never silently mix.
  const bytes = await loadWasmBytes(options);
  const module = new WebAssembly.Module(bytes);
  if (assetState) {
    const declared = WebAssembly.Module.imports(module);
    if (declared.some((entry) => entry.module === "passport" && entry.name === "host_pcm_write")) {
      throw new Error(
        "passport-host: this app.wasm imports passport.host_pcm_write (streamed PCM mode) " +
          "but the host is configured for PCM asset playback (pcmAssetUrl/pcmAssetBytes). " +
          "The two producer modes are mutually exclusive: remove the pcmAsset* options, " +
          "or serve an app that does not stream PCM itself.",
      );
    }
  }
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
  if (assetState) loadPcmAsset(state); // async by design: app frames never wait on it

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
 * @property {() => {bytesReceived: number, calls: number, droppedSamples: number}} pcmStats
 *   - host_pcm_write totals (wasm path only). droppedSamples is an extra
 *   observability field beyond the frozen minimum.
 * @property {() => boolean} audioAssetLoaded - PCM asset bytes resident.
 * @property {() => number} audioAssetSamples - total PCM samples of the asset.
 * @property {() => bigint} audioAssetDurationUs - one full pass of the asset.
 * @property {() => boolean} audioAssetLooping - whether pcmLoop is on.
 * @property {() => number} audioAssetLoops - completed CONSUMPTION passes
 *   (floor(consumedSamples / assetSamples)); 0 before playback.
 * @property {() => object} audioAsset - full facts snapshot for tooling
 *   (configured/source/url/loaded/error/samples/byteLength/durationUs/
 *   looping/cursor/eof/chunkSamples/chunksDecoded/maxChunkSamples/
 *   peakPendingSamples/loops).
 * @property {() => Promise<void>} waitForAudioAsset - resolves when the asset
 *   bytes are loaded (immediately when no asset is configured); rejects on
 *   fetch/validation failure without ever blocking app frames.
 * @property {(v: number) => void} setVolume
 * @property {(b: boolean|number) => void} setMuted
 * @property {() => bigint} playbackPosUs - best-effort µs; 0n before playback.
 * @property {(button: number, pressed: boolean|number) => void} queueInput
 * @property {(pcm: Int16Array|ArrayBuffer) => void} feedNormalizedPcm
 * @property {(nowUs?: bigint|number) => {frameCount: number, presented: boolean}|null} tick
 *   - run exactly one frame cycle manually (tests drive frames without rAF).
 * @property {() => void} start - rAF loop (setInterval fallback in Node).
 * @property {() => void} stop
 * @property {() => void} resumeAudio - called on first user gesture in browser.
 * @property {() => Uint16Array} getFramebufferView - 19200-entry RGB565 view
 *   (re-created transparently after wasm memory growth).
 * @property {(report: {filled?: number, consumed?: number, underruns?: number, dropped?: number}) => void} onAudioReport
 *   - normally wired to the worklet port; tests may call it to simulate
 *   consumption and exercise playbackPosUs deterministically.
 * @property {() => void} dispose
 * @property {object} imports - the "passport" import object used.
 * @property {object} exports - the app's wasm exports.
 * @property {WebAssembly.Memory} memory
 * @property {object} audio - { enabled, kind, ctx, gain, node, underruns,
 *   dropped, workletError, reason }.
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
    get pcmStats() {
      return { ...state.pcmStats };
    },
    get audioAssetLoaded() {
      return !!(state.asset && state.asset.loaded);
    },
    get audioAssetSamples() {
      return state.asset && state.asset.loaded ? state.asset.samples : 0;
    },
    get audioAssetDurationUs() {
      return state.asset && state.asset.loaded ? assetDurationUsValue(state.asset.samples) : 0n;
    },
    get audioAssetLooping() {
      return !!(state.asset && state.asset.loop);
    },
    get audioAssetLoops() {
      if (!state.asset || !state.asset.loaded) return 0;
      const consumed = state.posSnapshot ? state.posSnapshot.samples : 0;
      return Math.floor(consumed / state.asset.samples);
    },
    get audioAsset() {
      return assetDetail(state);
    },
    waitForAudioAsset: () => (state.asset ? state.asset.readyPromise : Promise.resolve()),
    setVolume: (value) => setVolume(state, value),
    setMuted: (value) => setMuted(state, value),
    playbackPosUs: () => playbackPosUs(state),
    queueInput: (button, pressed) => queueInput(state, button, pressed),
    feedNormalizedPcm: (input) => feedNormalizedPcm(state, input),
    tick: (nowUs) => tickOnce(state, nowUs),
    start: () => startLoop(state),
    stop: () => stopLoop(state),
    resumeAudio: () => resumeAudio(state),
    getFramebufferView: () => {
      ensureViews(state);
      return state.fbView;
    },
    onAudioReport: (report) => onAudioReport(state, report),
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
  // Resolve the page URL parameters HERE: createHost reads them for its own
  // defaults (battery/scale), but this scope builds the pcmAssetUrl/pcmLoop
  // options from ?pcm= / ?pcmLoop= itself and previously referenced `params`
  // without ever defining it (ReferenceError: auto-boot died before createHost).
  const params = readUrlParams();
  try {
    const hostOptions = { canvas };
    // ?pcm=<url> + ?pcmLoop=1: generic PCM asset configuration through the
    // page URL (host configuration only — no app semantics, no default asset).
    if (params.pcm !== undefined && params.pcm !== "") hostOptions.pcmAssetUrl = params.pcm;
    if (params.pcmLoop === "1" || params.pcmLoop === "true") hostOptions.pcmLoop = true;
    const host = await createHost(hostOptions);
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
