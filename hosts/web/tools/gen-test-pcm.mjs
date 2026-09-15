#!/usr/bin/env node
/**
 * gen-test-pcm.mjs — generate hosts/web/assets/test.pcm.
 *
 * The asset is the FIRST 4000 SAMPLES (0.25 s) of the frozen integer square
 * wave (frozen fixture contract, mirrors src/fixture/frame.mbt):
 *
 *     sample(n) = ((n >> 4) & 1) == 1 ? -4000 : 4000
 *
 * i.e. 500 Hz at 16000 Hz, amplitude 4000 PCM16, written as PCM16
 * little-endian mono 16000 Hz (8000 bytes). This is the exact waveform the
 * fixture app streams through host_pcm_write from its global sample counter
 * (266 samples per passport_frame), so tests can compare the asset and the
 * captured wasm PCM sample-for-sample.
 *
 * Deterministic and idempotent: running it twice must be byte-identical.
 */
import { createHash } from "node:crypto";
import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SAMPLE_COUNT = 4000;
const SAMPLE_RATE = 16000;
const AMPLITUDE = 4000;

const toolDir = path.dirname(fileURLToPath(import.meta.url));
const outPath = path.resolve(toolDir, "..", "assets", "test.pcm");

/** Frozen fixture waveform (integer-only, mirrors src/fixture/frame.mbt). */
function squareWave(n) {
  return ((n >> 4) & 1) === 1 ? -AMPLITUDE : AMPLITUDE;
}

const bytes = Buffer.alloc(SAMPLE_COUNT * 2); // PCM16 LE, explicit little-endian
for (let n = 0; n < SAMPLE_COUNT; n++) {
  bytes.writeInt16LE(squareWave(n), n * 2);
}

if (bytes.length !== 8000) {
  throw new Error(`gen-test-pcm: expected 8000 bytes, produced ${bytes.length}`);
}

mkdirSync(path.dirname(outPath), { recursive: true });
writeFileSync(outPath, bytes);

const sha256 = createHash("sha256").update(bytes).digest("hex");
console.log(`wrote ${outPath}`);
console.log(
  `samples: ${SAMPLE_COUNT} (${(SAMPLE_COUNT / SAMPLE_RATE).toFixed(2)} s at ${SAMPLE_RATE} Hz), bytes: ${bytes.length}`,
);
console.log(`sha256: ${sha256}`);
