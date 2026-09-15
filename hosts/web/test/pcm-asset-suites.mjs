/**
 * pcm-asset-suites.mjs — deterministic node suites for the SDK web host's
 * PCM ASSET transport (R1.2). Registered into run-tests.mjs's suite registry
 * via registerPcmAssetSuites(ctx); the runner provides the assertion helpers
 * and the host module (see run-tests.mjs "Suite registry").
 *
 * What these suites pin (mirrors the R1.2 contract):
 *
 *   - the minimal no-import wasm module used for asset-mode boots
 *   - strict input: only PCM16 LE mono 16000 Hz raw bytes (even, non-empty);
 *     odd/empty/404 assets fail the ASSET, never the app frames
 *   - non-blocking load: ticks run while the fetch is still in flight
 *   - exact decode: PCM16 -> Float32 (/32768) sample-for-sample
 *   - bounded refill: fixed 3200-sample decode chunks, bounded pending queue,
 *     no whole-track Float32 (maxChunkSamples/peakPendingSamples proofs)
 *   - sample-exact loop: [A B C] -> A B C A B C ... with no boundary defect
 *   - non-loop EOF: playback stops after the last sample, silence after
 *   - mute/volume: gain changes only; cursor + playback position continue
 *   - suspended AudioContext: app ticks keep running, nothing blocks
 *   - producer-mode exclusivity: asset config + host_pcm_write fails loudly
 *
 * All ScriptProcessor-based: the host's SP fallback drains the SAME decoded
 * queue as the AudioWorklet path, deterministically, inside node.
 */
import http from "node:http";
import { buildMinimalPassportWasm } from "./minimal-wasm.mjs";

const SAMPLE_RATE = 16000;
const CHUNK_SAMPLES = 3200; // mirrors ASSET_CHUNK_SAMPLES (asserted via detail.chunkSamples)
const SP_SAMPLES = 4096; // mirrors SCRIPT_PROCESSOR_SAMPLES
/** Frozen fixture waveform (integer-only, mirrors hosts/web/tools/gen-test-pcm.mjs). */
const squareWave = (n) => (((n >> 4) & 1) === 1 ? -4000 : 4000);

/** PCM16 LE bytes from int16 sample values. */
function pcmBytes(values) {
  const buf = new ArrayBuffer(values.length * 2);
  const dv = new DataView(buf);
  for (let i = 0; i < values.length; i++) dv.setInt16(i * 2, values[i], true);
  return buf;
}

/** Fake AudioContext selecting the host's ScriptProcessor fallback: pulls are
 *  driven manually (deterministic), currentTime is mutated by the test. */
function makeScriptAudioFake(initialState = "running") {
  const gain = { gain: { value: 1 }, connect() {} };
  let sp = null;
  const ctx = {
    currentTime: 0,
    state: initialState,
    destination: {},
    createGain: () => gain,
    createScriptProcessor: (size) => {
      sp = { bufferSize: size, onaudioprocess: null, connect() {} };
      return sp;
    },
  };
  return { ctx, gain, get sp() { return sp; } };
}

/** One deterministic ScriptProcessor pull; returns the filled output. */
function pull(sp) {
  const out = new Float32Array(sp.bufferSize);
  sp.onaudioprocess({ outputBuffer: { getChannelData: (ch) => (ch === 0 ? out : null) } });
  return out;
}

/** Throwaway http server answering one route with a delay (fetch tests). */
function startAssetServer(handler) {
  const server = http.createServer(handler);
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => resolve({ server, url: `http://127.0.0.1:${server.address().port}` }));
  });
}

/**
 * @param {object} ctx - { suite, ok, eq, eqText, throwsType, SuiteError,
 *   hostModule, repoRoot, releaseWasmPath } from run-tests.mjs.
 */
export function registerPcmAssetSuites(ctx) {
  const { suite, ok, eq, throwsType, SuiteError, hostModule, releaseWasmPath } = ctx;
  const fs = ctx.fs;

  /** Async counterpart of throwsType: createHost reports config errors as
   *  rejections (it is an async function), never as synchronous throws. */
  async function rejectsType(fn, ctor, msg) {
    let threw = null;
    try {
      await fn();
    } catch (err) {
      threw = err;
    }
    ok(threw !== null, `${msg}: expected ${ctor.name} rejection but nothing was thrown`);
    ok(threw instanceof ctor, `${msg}: expected ${ctor.name}, got ${threw?.constructor?.name}: ${threw}`);
  }

  let minimalBytes; // built once, shared by the asset suites
  suite("pcm-asset: minimal wasm module (no passport imports)", () => {
    minimalBytes = buildMinimalPassportWasm();
    const again = buildMinimalPassportWasm();
    ok(Buffer.compare(Buffer.from(minimalBytes), Buffer.from(again)) === 0, "emitter must be deterministic");

    const mod = new WebAssembly.Module(minimalBytes);
    eq(WebAssembly.Module.imports(mod).length, 0, "minimal module must import NOTHING (no host_pcm_write)");

    // Boot it through the host in ASSET mode with valid bytes: proves the
    // module satisfies the required export surface + fb geometry contract.
    const audio = makeScriptAudioFake();
    return hostModule
      .createHost({
        wasmBytes: minimalBytes,
        pcmAssetBytes: pcmBytes([1, -1]),
        pcmLoop: true,
        audioContextFactory: () => audio.ctx,
        nowUs: () => 0n,
      })
      .then(async (host) => {
        eq(host.exports.passport_fb_ptr(), 4096, "minimal passport_fb_ptr");
        eq(host.exports.passport_fb_len(), 38400, "minimal passport_fb_len");
        eq(host.exports.passport_frame_dirty(), 1, "minimal module is always dirty (canvas presents every tick)");
        const r = host.tick(0x12345n);
        ok(r !== null && r.presented, "asset-mode tick presents");
        eq(host.getFramebufferView()[0], 0x2345, "passport_frame stores low16(now_us) at framebuffer pixel 0");
        await host.waitForAudioAsset();
        eq(host.audioAssetLoaded, true, "asset loads under the minimal module");
        host.dispose();
      });
  });

  suite("pcm-asset: strict input, non-blocking load, config validation", async () => {
    // --- exact decode: PCM16 LE -> Float32 (/32768), sample-for-sample ---
    {
      const audio = makeScriptAudioFake();
      const values = [0, 1, -1, 32767, -32768, 4000, -4000];
      const host = await hostModule.createHost({
        wasmBytes: minimalBytes,
        pcmAssetBytes: pcmBytes(values),
        audioContextFactory: () => audio.ctx,
        nowUs: () => 0n,
      });
      await host.waitForAudioAsset();
      const out = pull(audio.sp);
      for (let i = 0; i < values.length; i++) {
        eq(out[i], values[i] / 32768, `decoded sample ${i} (${values[i]}/32768)`);
      }
      for (let i = values.length; i < out.length; i++) {
        eq(out[i], 0, `silence after EOF sample ${i} (non-loop default)`);
      }
      host.dispose();
    }

    // --- odd byte length: asset fails loudly, host keeps running ---
    {
      const audio = makeScriptAudioFake();
      const host = await hostModule.createHost({
        wasmBytes: minimalBytes,
        pcmAssetBytes: new ArrayBuffer(3),
        audioContextFactory: () => audio.ctx,
        nowUs: () => 0n,
      });
      let rejected = null;
      await host.waitForAudioAsset().catch((err) => (rejected = err));
      ok(rejected !== null, "odd-length asset must reject waitForAudioAsset");
      ok(String(rejected.message).includes("not even"), `odd-length error must name the format; got: ${rejected.message}`);
      eq(host.audioAssetLoaded, false, "odd-length asset never loads");
      ok(String(host.audioAsset.error).includes("not even"), "detail snapshot carries the error");
      ok(host.tick(1n) !== null, "app frames keep running after asset rejection");
      host.dispose();
    }

    // --- empty asset: rejected ---
    {
      const audio = makeScriptAudioFake();
      const host = await hostModule.createHost({
        wasmBytes: minimalBytes,
        pcmAssetBytes: new ArrayBuffer(0),
        audioContextFactory: () => audio.ctx,
        nowUs: () => 0n,
      });
      let rejected = null;
      await host.waitForAudioAsset().catch((err) => (rejected = err));
      ok(rejected !== null && rejected.message.includes("0 samples"), `empty asset error; got: ${rejected?.message}`);
      eq(host.audioAssetLoaded, false, "empty asset never loads");
      host.dispose();
    }

    // --- 404 fetch + non-blocking delayed fetch ---
    {
      const pcm = pcmBytes([7, -7, 700]);
      const { server, url } = await startAssetServer((req, res) => {
        if (req.url === "/missing.pcm") {
          res.writeHead(404, { "content-type": "text/plain" });
          res.end("no");
        } else if (req.url === "/slow.pcm") {
          setTimeout(() => {
            res.writeHead(200, { "content-type": "application/octet-stream" });
            res.end(Buffer.from(pcm));
          }, 150);
        } else {
          res.writeHead(500);
          res.end();
        }
      });
      try {
        const audio = makeScriptAudioFake();
        const host404 = await hostModule.createHost({
          wasmBytes: minimalBytes,
          pcmAssetUrl: `${url}/missing.pcm`,
          audioContextFactory: () => audio.ctx,
          nowUs: () => 0n,
        });
        let rejected = null;
        await host404.waitForAudioAsset().catch((err) => (rejected = err));
        ok(rejected !== null && rejected.message.includes("HTTP 404"), `fetch failure error; got: ${rejected?.message}`);
        eq(host404.audioAssetLoaded, false, "404 asset never loads");
        ok(host404.tick(1n) !== null, "frames continue after fetch failure");
        host404.dispose();

        // Non-blocking load: frames tick WHILE the (150 ms) fetch is pending.
        const audio2 = makeScriptAudioFake();
        const host = await hostModule.createHost({
          wasmBytes: minimalBytes,
          pcmAssetUrl: `${url}/slow.pcm`,
          pcmLoop: true,
          audioContextFactory: () => audio2.ctx,
          nowUs: () => 0n,
        });
        for (let n = 0; n < 5; n++) {
          const r = host.tick(BigInt(n) * 16000n);
          ok(r !== null && r.presented, `tick N=${n} runs while the asset fetch is pending`);
        }
        eq(host.frameCount, 5, "five frames ran before the asset arrived");
        eq(host.audioAssetLoaded, false, "asset not loaded yet (fetch deliberately slow)");
        await host.waitForAudioAsset();
        eq(host.audioAssetLoaded, true, "asset loads after the fetch completes");
        eq(host.audioAssetSamples, 3, "assetSamples (6 bytes / 2)");
        eq(host.audioAssetDurationUs, 188n, "assetDurationUs = round(3 samples * 1e6/16000) = round(187.5) = 188");
        host.dispose();
      } finally {
        server.close();
      }
    }

    // --- synchronous-looking config validation (reported as rejections) ---
    await rejectsType(
      () => hostModule.createHost({ wasmBytes: minimalBytes, pcmAssetUrl: "x", pcmAssetBytes: pcmBytes([1]) }),
      TypeError,
      "pcmAssetUrl + pcmAssetBytes together must throw",
    );
    await rejectsType(
      () => hostModule.createHost({ wasmBytes: minimalBytes, pcmLoop: true }),
      TypeError,
      "pcmLoop without a source must throw",
    );
    await rejectsType(
      () => hostModule.createHost({ wasmBytes: minimalBytes, pcmAssetUrl: 42 }),
      TypeError,
      "non-string pcmAssetUrl must throw",
    );

    // --- facts on a NON-asset host: neutral zeros, waitFor resolves ---
    {
      const host = await hostModule.createHost({ wasmBytes: minimalBytes, nowUs: () => 0n });
      eq(host.audioAssetLoaded, false, "non-asset host: audioAssetLoaded false");
      eq(host.audioAssetSamples, 0, "non-asset host: audioAssetSamples 0");
      eq(host.audioAssetDurationUs, 0n, "non-asset host: audioAssetDurationUs 0n");
      eq(host.audioAssetLooping, false, "non-asset host: audioAssetLooping false");
      eq(host.audioAssetLoops, 0, "non-asset host: audioAssetLoops 0");
      eq(host.audioAsset.configured, false, "non-asset host: detail.configured false");
      await host.waitForAudioAsset(); // resolves immediately
      host.dispose();
    }
  });

  suite("pcm-asset: bounded refill (no whole-track Float32)", async () => {
    const TOTAL = 40000; // 2.5 s — 12.5x the 3200-sample decode chunk
    const asset = pcmBytes(Array.from({ length: TOTAL }, (_, n) => squareWave(n)));
    const audio = makeScriptAudioFake();
    const host = await hostModule.createHost({
      wasmBytes: minimalBytes,
      pcmAssetBytes: asset,
      pcmLoop: true,
      audioContextFactory: () => audio.ctx,
      nowUs: () => 0n,
    });
    await host.waitForAudioAsset();

    const detail0 = host.audioAsset;
    eq(detail0.chunkSamples, CHUNK_SAMPLES, "decode chunk size is the fixed 3200");
    ok(detail0.maxChunkSamples <= CHUNK_SAMPLES, `first-fill chunks stay <= 3200 (max ${detail0.maxChunkSamples})`);
    ok(detail0.pendingSamples <= SP_SAMPLES * 2 + CHUNK_SAMPLES, `pending queue bounded (script-mode budget; got ${detail0.pendingSamples})`);
    ok(detail0.pendingSamples > 0, "initial refill queued something");
    ok(detail0.chunksDecoded >= 1, "at least one chunk decoded");

    // Pull 30 buffers (122880 samples > 3 asset passes). Every output sample
    // must equal the frozen square wave at its GLOBAL index — proving the
    // cursor advances exactly and chunks decode in order.
    let consumed = 0;
    let midChunksDecoded = -1;
    for (let pullIdx = 0; pullIdx < 30; pullIdx++) {
      const out = pull(audio.sp);
      for (let i = 0; i < out.length; i++) {
        const expected = squareWave(consumed + i) / 32768;
        if (out[i] !== expected) {
          throw new SuiteError(`stream mismatch at global sample ${consumed + i}: expected ${expected}, got ${out[i]}`);
        }
      }
      consumed += out.length;
      audio.ctx.currentTime += 0.25;
      if (pullIdx === 10) midChunksDecoded = host.audioAsset.chunksDecoded;
    }
    const detail1 = host.audioAsset;
    ok(detail1.chunksDecoded > midChunksDecoded, "decode is incremental: more chunks decoded as consumption proceeded");
    ok(detail1.maxChunkSamples <= CHUNK_SAMPLES, `no chunk ever exceeded 3200 samples (no whole-track Float32); max ${detail1.maxChunkSamples}`);
    ok(
      detail1.peakPendingSamples <= SP_SAMPLES * 2 + CHUNK_SAMPLES,
      `pending queue never exceeded the script-mode budget; peak ${detail1.peakPendingSamples}`,
    );
    ok(host.audioAssetLoops >= 3, `consumption crossed >= 3 asset passes (floor(${consumed}/40000)); got ${host.audioAssetLoops}`);
    const cursorMin = consumed % TOTAL;
    ok(
      detail1.cursor >= cursorMin && detail1.cursor <= cursorMin + SP_SAMPLES * 2 + CHUNK_SAMPLES,
      `decode cursor stays within one budget ahead of consumption (cursor ${detail1.cursor}, consumed mod ${cursorMin})`,
    );
    ok(host.playbackPosUs() > 0n, "playback position advanced");
    host.dispose();
  });

  suite("pcm-asset: sample-exact loop", async () => {
    const TRI = [1000, -2000, 3000];
    const audio = makeScriptAudioFake();
    const host = await hostModule.createHost({
      wasmBytes: minimalBytes,
      pcmAssetBytes: pcmBytes(TRI),
      pcmLoop: true,
      audioContextFactory: () => audio.ctx,
      nowUs: () => 0n,
    });
    await host.waitForAudioAsset();
    eq(host.audioAssetLooping, true, "audioAssetLooping true");
    eq(host.audioAssetSamples, 3, "three-sample asset");

    let consumed = 0;
    for (let pullIdx = 0; pullIdx < 2; pullIdx++) {
      const out = pull(audio.sp);
      for (let i = 0; i < out.length; i++) {
        const expected = TRI[(consumed + i) % 3] / 32768;
        if (out[i] !== expected) {
          throw new SuiteError(
            `loop boundary defect at global sample ${consumed + i} (index ${i} of pull ${pullIdx}): expected ${expected}, got ${out[i]}`,
          );
        }
      }
      consumed += out.length;
      audio.ctx.currentTime += 0.25;
    }
    // Explicit seam proof: global samples 2999|3000|3001 and 5999|6000|6001
    // are C|A|B and B|C|A — no missing, duplicated, or silenced boundary sample.
    const out2 = pull(audio.sp);
    eq(out2[0], TRI[consumed % 3] / 32768, "third pull continues the exact cycle");
    ok(host.audioAssetLoops >= Math.floor((consumed + out2.length) / 3) - 1, "consumption-based loop count advanced");
    eq(host.audioAsset.eof, false, "looping asset never reaches EOF");
    host.dispose();
  });

  suite("pcm-asset: non-loop EOF terminates after the last sample", async () => {
    const TRI = [5000, -5000, 12000];
    const audio = makeScriptAudioFake();
    const host = await hostModule.createHost({
      wasmBytes: minimalBytes,
      pcmAssetBytes: pcmBytes(TRI),
      pcmLoop: false,
      audioContextFactory: () => audio.ctx,
      nowUs: () => 0n,
    });
    await host.waitForAudioAsset();
    eq(host.audioAssetLooping, false, "pcmLoop defaults to false");

    const out1 = pull(audio.sp);
    eq(out1[0], 5000 / 32768, "EOF pass sample 0");
    eq(out1[1], -5000 / 32768, "EOF pass sample 1");
    eq(out1[2], 12000 / 32768, "EOF pass sample 2 (last)");
    for (let i = 3; i < out1.length; i++) eq(out1[i], 0, `silence after last sample (index ${i})`);
    const detail1 = host.audioAsset;
    eq(detail1.eof, true, "EOF reached");
    eq(detail1.cursor, 3, "cursor parked at the sample count");
    eq(detail1.chunksDecoded, 1, "exactly one decode chunk for the whole pass");
    eq(host.playbackPosUs(), 188n, "position = round(3 samples * 62.5 us) = 188 us");

    const chunksBefore = detail1.chunksDecoded;
    const out2 = pull(audio.sp); // nothing left: pure silence, no restart
    for (let i = 0; i < out2.length; i++) eq(out2[i], 0, `second pull is silent (index ${i})`);
    const detail2 = host.audioAsset;
    eq(detail2.chunksDecoded, chunksBefore, "no further decode after EOF");
    eq(detail2.cursor, 3, "cursor frozen at EOF");
    eq(host.playbackPosUs(), 188n, "position frozen at exactly the asset length");
    eq(host.audioAssetLoops, 1, "exactly one completed pass in non-loop mode (never more)");
    host.dispose();
  });

  suite("pcm-asset: mute/volume change gain only (clock + cursor continue)", async () => {
    const TRI = [1000, -2000, 3000];
    const audio = makeScriptAudioFake();
    const host = await hostModule.createHost({
      wasmBytes: minimalBytes,
      pcmAssetBytes: pcmBytes(TRI),
      pcmLoop: true,
      audioContextFactory: () => audio.ctx,
      nowUs: () => 0n,
    });
    await host.waitForAudioAsset();
    eq(audio.gain.gain.value, 1, "initial master gain 1 (volume 100, unmuted)");

    pull(audio.sp);
    audio.ctx.currentTime += 0.25;
    pull(audio.sp);
    audio.ctx.currentTime += 0.25;
    const posBeforeMute = host.playbackPosUs();
    const detailBeforeMute = host.audioAsset;
    const loopsBeforeMute = host.audioAssetLoops;
    ok(posBeforeMute > 0n, "position advanced before muting");

    host.setMuted(true);
    eq(audio.gain.gain.value, 0, "mute forces gain 0");
    eq(host.audioAsset.cursor, detailBeforeMute.cursor, "muting does not move the source cursor");
    pull(audio.sp);
    audio.ctx.currentTime += 0.25;
    pull(audio.sp);
    audio.ctx.currentTime += 0.25;
    ok(host.playbackPosUs() > posBeforeMute, "playback position KEEPS RUNNING while muted");
    ok(host.audioAssetLoops > loopsBeforeMute, "consumption continues while muted");
    ok(
      host.audioAsset.chunksDecoded > detailBeforeMute.chunksDecoded,
      "decode/refill continued while muted (looping)",
    );

    const cursorAfterVolume = host.audioAsset.cursor;
    host.setVolume(37); // while muted: gain stays 0, source untouched
    eq(audio.gain.gain.value, 0, "volume change while muted keeps gain 0");
    eq(host.audioAsset.cursor, cursorAfterVolume, "volume does not alter the source cursor");
    host.setMuted(false);
    eq(audio.gain.gain.value, 0.37, "unmute maps volume 37 -> gain 0.37");
    const posAfterUnmute = host.playbackPosUs();
    pull(audio.sp);
    audio.ctx.currentTime += 0.25;
    ok(host.playbackPosUs() >= posAfterUnmute, "position monotonic across mute toggles");
    ok(host.tick(999n) !== null, "app frames keep running throughout");
    host.dispose();
  });

  suite("pcm-asset: suspended AudioContext never blocks app frames", async () => {
    const audio = makeScriptAudioFake("suspended");
    const host = await hostModule.createHost({
      wasmBytes: minimalBytes,
      pcmAssetBytes: pcmBytes([4000, -4000]),
      pcmLoop: true,
      audioContextFactory: () => audio.ctx,
      nowUs: () => 0n,
    });
    await host.waitForAudioAsset();
    eq(host.audioAssetLoaded, true, "asset bytes resident while the context is suspended");
    ok(host.audioAsset.pendingSamples > 0, "initial refill happened without any consumption");

    for (let n = 0; n < 10; n++) {
      const r = host.tick(BigInt(n) * 16000n);
      ok(r !== null && r.presented, `tick N=${n} presents while audio is suspended`);
    }
    eq(host.frameCount, 10, "ten frames ran with zero audio consumption");
    eq(host.playbackPosUs(), 0n, "position stays 0n while suspended (nothing consumed)");
    host.resumeAudio(); // no-op on the fake (no resume method => ignored); must not throw

    // Simulate the user gesture: context runs, pulls start arriving.
    audio.ctx.state = "running";
    audio.ctx.currentTime = 1.0;
    const out = pull(audio.sp);
    eq(out[0], 4000 / 32768, "audio starts through the same transport after unlock");
    audio.ctx.currentTime = 1.25;
    pull(audio.sp);
    ok(host.playbackPosUs() > 0n, "position advances once consumption begins");
    ok(host.tick(11n * 16000n) !== null, "frames still run after unlock");
    host.dispose();
  });

  suite("pcm-asset: producer modes are explicitly exclusive", async () => {
    // The real fixture wasm imports passport.host_pcm_write: an asset-configured
    // boot must fail LOUDLY at createHost, before anything runs.
    const fixtureBytes = fs.readFileSync(releaseWasmPath);
    let conflict = null;
    await hostModule
      .createHost({
        wasmBytes: fixtureBytes,
        pcmAssetBytes: pcmBytes([1, -1]),
        audioContextFactory: () => makeScriptAudioFake().ctx,
      })
      .catch((err) => (conflict = err));
    ok(conflict !== null, "fixture wasm + pcmAssetBytes must fail at boot");
    ok(
      String(conflict.message).includes("host_pcm_write") && String(conflict.message).includes("pcmAsset"),
      `exclusivity error must name both modes; got: ${conflict.message}`,
    );

    // On an asset host, the streamed test seam and the default import refuse.
    const audio = makeScriptAudioFake();
    const host = await hostModule.createHost({
      wasmBytes: minimalBytes,
      pcmAssetBytes: pcmBytes([1, -1]),
      pcmLoop: true,
      audioContextFactory: () => audio.ctx,
      nowUs: () => 0n,
    });
    await host.waitForAudioAsset();
    throwsType(() => host.feedNormalizedPcm(pcmBytes([1])), TypeError, "feedNormalizedPcm refuses asset hosts");
    throwsType(
      () => host.imports.passport.host_pcm_write(0, 1),
      Error,
      "default host_pcm_write import refuses asset hosts",
    );
    eq(host.pcmStats.calls, 0, "no streamed-PCM accounting on an asset host");
    host.dispose();

    // And the minimal module WITHOUT asset options stays a plain streamed host.
    const plain = await hostModule.createHost({
      wasmBytes: minimalBytes,
      audioContextFactory: () => makeScriptAudioFake().ctx,
      nowUs: () => 0n,
    });
    plain.feedNormalizedPcm(new Int16Array([123, -123]));
    eq(plain.audioAssetLoaded, false, "no asset configured on the plain host");
    plain.dispose();
  });
}
