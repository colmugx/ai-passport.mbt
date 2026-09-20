#!/usr/bin/env node
/**
 * make-bundle.mjs — assemble a host-consumable test bundle (the directory
 * contract documented in hosts/web/README.md):
 *
 *     <outdir>/app.wasm          copy of the RELEASE fixture wasm
 *     <outdir>/sounds.bank       valid empty APSB v1 bank
 *     <outdir>/assets/test.pcm   copy of the generated PCM test asset
 *
 * Usage:
 *     node hosts/web/tools/make-bundle.mjs [outdir]
 *     (default outdir: <repo>/_build/passport-bundle)
 *
 * Environment (test seam only):
 *     PASSPORT_FIXTURE_WASM=<path>  use this wasm instead of the default
 *                                   release fixture artifact (used by the
 *                                   bundle suite to exercise the refusal
 *                                   path).
 *
 * This is test tooling for the distribution contract — NOT project
 * scaffolding and NOT an application.
 */
import { copyFileSync, existsSync, mkdirSync, statSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const toolDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(toolDir, "..", "..", ".."); // hosts/web/tools -> repository root

const defaultWasm = path.join(repoRoot, "_build", "wasm", "release", "build", "fixture", "fixture.wasm");
const wasmPath = process.env.PASSPORT_FIXTURE_WASM
  ? path.resolve(process.env.PASSPORT_FIXTURE_WASM)
  : defaultWasm;
const outDir = path.resolve(process.argv[2] || path.join(repoRoot, "_build", "passport-bundle"));
const assetSrc = path.join(repoRoot, "hosts", "web", "assets", "test.pcm");

if (!existsSync(wasmPath)) {
  console.error(`make-bundle: app wasm not found at ${wasmPath}`);
  console.error(`Build it first from the repo root (${repoRoot}):`);
  console.error("  moon build --target wasm --release   # release artifact (bundled here)");
  console.error("  moon build --target wasm             # debug artifact");
  process.exit(1);
}
if (!existsSync(assetSrc)) {
  console.error(`make-bundle: test.pcm not found at ${assetSrc}`);
  console.error("Generate it first:");
  console.error("  node hosts/web/tools/gen-test-pcm.mjs");
  process.exit(1);
}

mkdirSync(path.join(outDir, "assets"), { recursive: true });
copyFileSync(wasmPath, path.join(outDir, "app.wasm"));
copyFileSync(assetSrc, path.join(outDir, "assets", "test.pcm"));
writeFileSync(
  path.join(outDir, "sounds.bank"),
  Buffer.from([0x41, 0x50, 0x53, 0x42, 1, 0, 16, 0, 0, 0, 0, 0, 8, 0, 0, 0]),
);

const wasmSize = statSync(path.join(outDir, "app.wasm")).size;
console.log(`bundle: ${outDir}`);
console.log(`  app.wasm          (${wasmSize} bytes, from ${path.relative(repoRoot, wasmPath) || wasmPath})`);
console.log("  sounds.bank       (empty APSB v1)");
console.log(`  assets/test.pcm   (from ${path.relative(repoRoot, assetSrc)})`);
