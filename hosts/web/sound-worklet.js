/**
 * AudioWorklet renderer for APSB sound-bank playbacks.
 *
 * The main thread transfers one immutable bank, then controls independent
 * playback handles. This processor owns the sample cursors, mixes every live
 * source into one mono output, clamps once, and reports cursor snapshots.
 */

const REPORT_INTERVAL = 4;

class PassportSoundProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.soundEntries = [];
    this.playbacks = new Map();
    this.endedSinceReport = [];
    this.processCalls = 0;

    this.port.onmessage = (event) => {
      const msg = event.data;
      if (!msg || typeof msg !== "object") return;
      if (msg.type === "sound-bank" && msg.bank instanceof ArrayBuffer && Array.isArray(msg.entries)) {
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
    for (let i = 0; i < out.length; i++) {
      let mixed = 0;
      for (const playback of this.playbacks.values()) {
        if (playback.paused) continue;
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
    if ((this.processCalls++ & (REPORT_INTERVAL - 1)) === 0) {
      this.port.postMessage({
        type: "report",
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

registerProcessor("passport-sound", PassportSoundProcessor);
