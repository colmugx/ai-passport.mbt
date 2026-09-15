/**
 * pcm-worklet.js — AudioWorklet sink for the passport web host.
 *
 * Runs on the real-time audio thread. Receives Float32 chunks (already
 * normalized: int16 / 32768) over the message port and schedules them
 * gaplessly onto its single mono output at the context sample rate. The host
 * creates its AudioContext with `{ sampleRate: 16000 }`, matching the ABI v0
 * normalized PCM stream, so no resampling happens here.
 *
 * Underrun policy: output silence, never throw, never block.
 * Ring overflow: drop incoming samples (must not happen; the main thread
 * keeps only ~200 ms buffered against a ~1 s ring) — reported, not silent.
 *
 * Protocol (main thread -> worklet): { type: "pcm", data: Float32Array }
 *           (worklet -> main thread): { type: "report", filled, consumed,
 *           underruns, dropped } every 4th process() call (~32 ms at 16 kHz).
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

    this.port.onmessage = (event) => {
      const msg = event.data;
      if (!msg || msg.type !== "pcm" || !(msg.data instanceof Float32Array)) return;
      const chunk = msg.data;
      let copied = 0;
      while (copied < chunk.length && this.fill < this.ring.length) {
        this.ring[this.writeIdx] = chunk[copied++];
        this.writeIdx = (this.writeIdx + 1) & this.mask;
        this.fill++;
      }
      this.droppedTotal += chunk.length - copied;
    };
  }

  process(_inputs, outputs) {
    const out = outputs[0][0];
    let i = 0;
    const available = Math.min(out.length, this.fill);
    while (i < available) {
      out[i] = this.ring[this.readIdx];
      this.readIdx = (this.readIdx + 1) & this.mask;
      i++;
    }
    while (i < out.length) out[i++] = 0; // underrun: silence
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
      });
    }
    return true;
  }
}

registerProcessor("passport-pcm", PassportPcmProcessor);
