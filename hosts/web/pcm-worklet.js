/**
 * pcm-worklet.js — AudioWorklet sink for the passport web host.
 *
 * Runs on the real-time audio thread. It retains zero-copy Int16Array views
 * into the transferred APSB payload, advances independent playback cursors,
 * sums them with the transitional Float32 PCM ring, and clamps once onto its
 * mono output. The host creates its AudioContext with `{ sampleRate: 16000 }`,
 * so no SDK resampling exists here.
 *
 * Underrun policy: output silence, never throw, never block.
 * Ring overflow: drop incoming samples (must not happen; the main thread
 * keeps only ~200 ms buffered against a ~1 s ring) — reported, not silent.
 *
 * Protocol (main thread -> worklet): one `sound-bank`, then `sound-play`,
 * `sound-pause`, `sound-resume`, `sound-stop`; the legacy `pcm` message remains
 * until its transport is removed. Reports include per-handle sample cursors
 * and ended handles every fourth process call (~32 ms at 16 kHz).
 */

const DEFAULT_RING_SAMPLES = 16384; // ~1.0 s at 16 kHz (power of two)
const REPORT_INTERVAL = 4;

class PassportPcmProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    const opts = (options && options.processorOptions) || {};
    let ringSamples = opts.ringSamples | 0;
    if (ringSamples < 256 || (ringSamples & (ringSamples - 1)) !== 0) {
      ringSamples = DEFAULT_RING_SAMPLES;
    }
    this.ring = new Float32Array(ringSamples);
    this.mask = ringSamples - 1;
    this.readIdx = 0;
    this.writeIdx = 0;
    this.fill = 0;
    this.consumedTotal = 0;
    this.underrunCount = 0;
    this.droppedTotal = 0;
    this.processCalls = 0;
    this.soundEntries = [];
    this.playbacks = new Map();
    this.endedSinceReport = [];

    this.port.onmessage = (event) => {
      const msg = event.data;
      if (!msg || typeof msg !== "object") return;
      if (msg.type === "pcm" && msg.data instanceof Float32Array) {
        const chunk = msg.data;
        let copied = 0;
        while (copied < chunk.length && this.fill < this.ring.length) {
          this.ring[this.writeIdx] = chunk[copied++];
          this.writeIdx = (this.writeIdx + 1) & this.mask;
          this.fill++;
        }
        this.droppedTotal += chunk.length - copied;
      } else if (msg.type === "sound-bank" && msg.bank instanceof ArrayBuffer && Array.isArray(msg.entries)) {
        this.soundEntries = msg.entries.map((entry) =>
          new Int16Array(msg.bank, entry.offset, entry.sampleCount),
        );
      } else if (msg.type === "sound-play") {
        const samples = this.soundEntries[msg.soundId | 0];
        if (samples) {
          this.playbacks.set(msg.handle | 0, {
            handle: msg.handle | 0,
            samples,
            looping: !!msg.looping,
            paused: false,
            cursor: 0,
          });
        }
      } else if (msg.type === "sound-pause") {
        const playback = this.playbacks.get(msg.handle | 0);
        if (playback) playback.paused = true;
      } else if (msg.type === "sound-resume") {
        const playback = this.playbacks.get(msg.handle | 0);
        if (playback) playback.paused = false;
      } else if (msg.type === "sound-stop") {
        this.playbacks.delete(msg.handle | 0);
      }
    };
  }

  process(_inputs, outputs) {
    const out = outputs[0][0];
    const available = Math.min(out.length, this.fill);
    for (let i = 0; i < out.length; i++) {
      let mixed = 0;
      if (i < available) {
        mixed = this.ring[this.readIdx];
        this.readIdx = (this.readIdx + 1) & this.mask;
      }
      for (const playback of this.playbacks.values()) {
        if (playback.paused) continue;
        if (playback.cursor >= playback.samples.length) {
          if (playback.looping) {
            playback.cursor = 0;
          } else {
            this.playbacks.delete(playback.handle);
            this.endedSinceReport.push(playback.handle);
            continue;
          }
        }
        mixed += playback.samples[playback.cursor++] / 32768;
        if (playback.cursor >= playback.samples.length) {
          if (playback.looping) {
            playback.cursor = 0;
          } else {
            this.playbacks.delete(playback.handle);
            this.endedSinceReport.push(playback.handle);
          }
        }
      }
      out[i] = Math.max(-1, Math.min(32767 / 32768, mixed));
    }
    if (available < out.length) this.underrunCount++;
    this.consumedTotal += available;
    this.fill -= available; // free the consumed span: the ring must DRAIN, or
    // readIdx would wrap and replay stale samples forever while the reported
    // `filled` (which the main thread uses as its refill signal) never drops.
    if ((this.processCalls++ & (REPORT_INTERVAL - 1)) === 0) {
      this.port.postMessage({
        type: "report",
        filled: this.fill,
        consumed: this.consumedTotal,
        underruns: this.underrunCount,
        dropped: this.droppedTotal,
        playbacks: [...this.playbacks.values()].map((playback) => ({
          handle: playback.handle,
          positionSamples: playback.cursor,
        })),
        ended: this.endedSinceReport.splice(0),
      });
    }
    return true;
  }
}

registerProcessor("passport-pcm", PassportPcmProcessor);
