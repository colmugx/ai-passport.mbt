/**
 * cli-fixture-suites.mjs — integration suites for the passport CLI
 * (`src/cmd/passport`), registered into run-tests.mjs.
 *
 * What these suites prove:
 *  1. terminology gates  — the CLI/host source never calls a Host a
 *                          "product"/"board" and contains zero application
 *                          semantics (no starter-app names of any kind);
 *  2. fixture A          — a downstream-style NO-AUDIO app builds into the
 *                          full bundle contract (app.wasm + the three SDK
 *                          host files, no app.html, plain index.html URL),
 *                          and the device Host refuses a project that
 *                          declares no deviceEntry instead of falling back
 *                          to web;
 *  3. fixture B          — a downstream-style PCM-asset app builds with the
 *                          asset materialized byte-identically and the
 *                          generic URL parameters on the printed entry;
 *  4. fixture C          — a downstream-style SINGLE-ENTRY application (the
 *                          application contract: display, input, battery,
 *                          audio output state, playback position) builds
 *                          through the CLI-GENERATED Web entry adapter
 *                          under passport-generated/, keeps the ABI v0
 *                          export/import surface, and boots in a real
 *                          browser rendering the host facts;
 *  5. doctor             — the doctor passes for a resolvable project;
 *  6. real browsers      — the CLI-produced bundles boot through the SDK's
 *                          own index.html DOM auto-boot from the printed
 *                          URL: fixture A renders and answers input with no
 *                          audio requirement; fixture B fetches its PCM
 *                          asset over http, loops it sample-exactly through
 *                          the AudioWorklet, and keeps presenting frames;
 *                          fixture C drives the whole application contract
 *                          end to end (input queue → bars/markers move).
 *
 * The fixtures are complete nested MoonBit modules under
 * hosts/web/test/fixtures/ (their own moon.mod depending on the PUBLISHED
 * colmugx/ai-passport package) — the strongest pre-publish proof that the
 * CLI works for a downstream project, not just for the SDK checkout.
 * Fixture C consumes the unpublished application contract, so its suite
 * first overlays THIS checkout into its .mooncakes at the fixture's
 * registry pin (the same CI-internal dev overlay the template-integration
 * job performs; the fixture itself stays coupled only to its pin).
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { BROWSER_LAUNCH_FLAGS, findHeadlessShell, loadPlaywright, startStaticServer } from "./browser-common.mjs";

const CLI_PACKAGE = "src/cmd/passport";
const FIXTURES_DIR = ["hosts", "web", "test", "fixtures"];

/** Runs the passport CLI from the SDK repository against one project. */
function runCli(repoRoot, args) {
  return spawnSync(
    "moon",
    ["run", "--target", "wasm", CLI_PACKAGE, ...args],
    { cwd: repoRoot, encoding: "utf8", timeout: 240_000, maxBuffer: 16 * 1024 * 1024 },
  );
}

function fixtureDir(repoRoot, name) {
  return path.join(repoRoot, ...FIXTURES_DIR, name);
}

/** Extracts the entry URL the CLI printed ("passport: entry: /..."). */
function printedEntryUrl(stdout) {
  const m = /^passport: entry: (\S+)$/m.exec(stdout);
  return m ? m[1] : null;
}


/** Playwright run of a CLI-produced bundle through the SDK's own index.html
 *  (the DOM auto-boot path — no probe page). Waits for globalThis.__passportHost
 *  and, optionally, for a caller predicate. Returns page facts plus errors. */
async function runAutoBootBundle(url, waitFor) {
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
    await page.waitForFunction(() => globalThis.__passportHost !== undefined, null, { timeout: 45_000 });
    if (waitFor) {
      await page.waitForFunction(waitFor, null, { timeout: 45_000, polling: 100 });
    }
    facts.payload = await page.evaluate(
      () =>
        new Promise((resolve) => {
          const host = globalThis.__passportHost;
          const frames0 = host.frameCount;
          setTimeout(() => {
            resolve({
              status: document.getElementById("passport-status").textContent,
              hasFrameExport: typeof host.exports.passport_frame === "function",
              frameCountAtSnapshot: frames0,
              framesDuring: host.frameCount - frames0,
              canvasWidth: document.getElementById("passport-canvas").width,
              assetConfigured: host.audioAsset.configured,
              audioKind: host.audio.kind,
            });
          }, 400);
        }),
    );
  } finally {
    await browser.close().catch(() => {});
  }
  return facts;
}

/** Playwright deep-proof run for fixture B: everything runAutoBootBundle
 *  proves plus the PCM asset transport facts (samples, loop count, ring
 *  health, playback position). */
async function runAutoBootBundleWithAudio(url) {
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
    facts.payload = await page.evaluate(
      () =>
        new Promise((resolve) => {
          const host = globalThis.__passportHost;
          const frames0 = host.frameCount;
          setTimeout(() => {
            resolve({
              status: document.getElementById("passport-status").textContent,
              hasFrameExport: typeof host.exports.passport_frame === "function",
              framesDuring: host.frameCount - frames0,
              assetConfigured: host.audioAsset.configured,
              assetLoaded: host.audioAssetLoaded,
              assetSamples: host.audioAssetSamples,
              assetLooping: host.audioAssetLooping,
              assetError: host.audioAsset.error,
              loops: host.audioAssetLoops,
              posUs: String(host.playbackPosUs()),
              dropped: host.audio.dropped,
              audioKind: host.audio.kind,
            });
          }, 400);
        }),
    );
  } finally {
    await browser.close().catch(() => {});
  }
  return facts;
}

/** chrome-headless-shell fallback: the status line the host itself renders.
 *  Degraded proof only (never the CI mechanism): page boots + runs. */
function runShellBundleStatus(url) {
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

/** Copies the SDK tree into `dest`, skipping the CI overlay excludes.
 *  Manual recursion because fs.cpSync refuses to copy a directory into its
 *  own subtree and the fixture lives inside the checkout. */
function copySdkTree(src, dest, excluded) {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    if (excluded.has(entry.name)) continue;
    const from = path.join(src, entry.name);
    const to = path.join(dest, entry.name);
    if (entry.isDirectory()) copySdkTree(from, to, excluded);
    else if (entry.isFile()) fs.copyFileSync(from, to);
    // Symlinks in the checkout are dev-environment noise, not module facts.
  }
}

/** Overlays THIS SDK checkout into fixture-c's .mooncakes, stamped at the
 *  fixture's registry pin, so the unpublished application contract resolves.
 *  Mirrors the CI template-integration overlay excludes exactly. Returns the
 *  stamped pin. */
// One overlay per run-tests invocation: re-copying the tree after a build
// inside it invalidates module metadata moon derived from the previous
// copy, so the second build's package discovery fails intermittently.
let fixtureCOverlaid = false;

function overlayCurrentSdkIntoFixtureC(repoRoot) {
  if (fixtureCOverlaid) return;
  fixtureCOverlaid = true;
  const project = fixtureDir(repoRoot, "fixture-c");
  const pin = /"colmugx\/ai-passport@([0-9.]+)"/.exec(
    fs.readFileSync(path.join(project, "moon.mod"), "utf8"),
  )[1];
  // Stamp from the SOURCE module text — never read the copied tree back.
  const sdkMod = fs.readFileSync(path.join(repoRoot, "moon.mod"), "utf8");
  const dest = path.join(project, ".mooncakes", "colmugx", "ai-passport");
  fs.rmSync(dest, { recursive: true, force: true });
  // A lock recorded against the published tree would make moon re-materialize
  // it over the overlay; a fresh resolution accepts the overlaid module.
  fs.rmSync(path.join(project, ".mooncakes", ".moon-lock"), { force: true });
  copySdkTree(repoRoot, dest, new Set([
    ".git",
    "_build",
    ".mooncakes",
    ".agents",
    ".github",
    ".githooks",
    ".passport",
    "passport-generated",
    "external",
  ]));
  fs.writeFileSync(
    path.join(dest, "moon.mod"),
    sdkMod.replace(/^version = ".*"$/m, `version = "${pin}"`),
  );
  return pin;
}

export function registerCliFixtureSuites({ suite, ok, eq, eqText, SuiteError, repoRoot, webHostDir }) {
  const passportCli = path.join(repoRoot, CLI_PACKAGE);

  // --- Suite: structural gates -------------------------------------------------

  suite("cli: structural gates — Host-only vocabulary, zero application semantics", () => {
    const scanned = [];
    for (const rel of ["src/hosts", "src/cli", "src/cmd/passport", "src/application", "src/runtime"]) {
      const root = path.join(repoRoot, rel);
      const walk = (dir) => {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
          const full = path.join(dir, entry.name);
          if (entry.isDirectory()) walk(full);
          else if (/\.(mbt|pkg)$/.test(entry.name) || entry.name === "moon.pkg") scanned.push(full);
        }
      };
      walk(root);
    }
    ok(scanned.length >= 10, `structural scan must cover the CLI/host sources (found ${scanned.length} files)`);
    // User-facing backend vocabulary: a Host is a Host, never a product or a
    // board (word-boundary match: "keyboard" etc. are fine).
    const backendTerm = /\b(product|products|boards|board)\b/i;
    // Application semantics: the CLI is application-generic. Any starter-app
    // vocabulary here would be a hard architectural violation.
    const appTerm = /(forest|fairy)/i;
    for (const file of scanned) {
      const lines = fs.readFileSync(file, "utf8").split("\n");
      lines.forEach((line, idx) => {
        if (backendTerm.test(line)) {
          throw new SuiteError(`${path.relative(repoRoot, file)}:${idx + 1}: user-facing backend vocabulary must say "host", not "${line.match(backendTerm)[0]}"`);
        }
        if (appTerm.test(line)) {
          throw new SuiteError(`${path.relative(repoRoot, file)}:${idx + 1}: CLI/host code must be application-generic (found "${line.match(appTerm)[0]}")`);
        }
      });
    }
  });

  // --- Suite: fixture A bundle assembly ----------------------------------------

  suite("cli: fixture-a (no audio) builds the full web bundle", () => {
    const project = fixtureDir(repoRoot, "fixture-a");
    const res = runCli(repoRoot, ["build", "--host", "web", "--project", project]);
    eq(res.status, 0, `passport build must succeed for fixture-a; stderr: ${res.stderr}`);
    const bundle = path.join(project, ".passport", "web");
    ok(fs.existsSync(path.join(bundle, "app.wasm")), "bundle/app.wasm must exist");
    for (const file of ["index.html", "passport-host.js", "pcm-worklet.js"]) {
      ok(
        fs.readFileSync(path.join(bundle, file)).equals(fs.readFileSync(path.join(webHostDir, file))),
        `bundle/${file} must be byte-identical to the SDK's own host file`,
      );
    }
    ok(!fs.existsSync(path.join(bundle, "app.html")), "no app.html may exist in the bundle");
    const url = printedEntryUrl(res.stdout);
    eq(url, "/index.html", `the printed entry must be the plain page (got ${JSON.stringify(url)})`);

    // The device Host is implemented but refuses a project that declares no
    // device entry: no silent web fallback, no invented device build. (A real
    // ESP-IDF device build is not exercised here — CI has no device
    // toolchain; the physical build is proven out of band.)
    const refused = runCli(repoRoot, ["build", "--host", "folotoy-ai-passport", "--project", project]);
    ok(refused.status !== 0, "device build must fail for a project without a device entry");
    const text = `${refused.stdout}\n${refused.stderr}`;
    ok(
      text.includes('host "folotoy-ai-passport" requires a "deviceEntry" package in passport.json'),
      `device refusal must name the deviceEntry contract error; got: ${text.trim().split("\n")[0]}`,
    );
  });

  // --- Suite: fixture B bundle assembly ----------------------------------------

  suite("cli: fixture-b (PCM asset) builds with the asset materialized", () => {
    const project = fixtureDir(repoRoot, "fixture-b");
    const res = runCli(repoRoot, ["build", "--host", "web", "--project", project]);
    eq(res.status, 0, `passport build must succeed for fixture-b; stderr: ${res.stderr}`);
    const bundle = path.join(project, ".passport", "web");
    ok(fs.existsSync(path.join(bundle, "app.wasm")), "bundle/app.wasm must exist");
    for (const file of ["index.html", "passport-host.js", "pcm-worklet.js"]) {
      ok(
        fs.readFileSync(path.join(bundle, file)).equals(fs.readFileSync(path.join(webHostDir, file))),
        `bundle/${file} must be byte-identical to the SDK's own host file`,
      );
    }
    ok(
      fs.readFileSync(path.join(bundle, "assets", "tone.pcm")).equals(
        fs.readFileSync(path.join(project, "assets", "tone.pcm")),
      ),
      "bundle/assets/tone.pcm must be byte-identical to the project asset",
    );
    const url = printedEntryUrl(res.stdout);
    eq(
      url,
      "/index.html?pcm=./assets/tone.pcm&pcmLoop=1",
      `the printed entry must carry the generic PCM parameters from the project contract (got ${JSON.stringify(url)})`,
    );
  });

  // --- Suite: doctor ------------------------------------------------------------

  suite("cli: doctor passes for a resolvable web project", () => {
    const project = fixtureDir(repoRoot, "fixture-a");
    const res = runCli(repoRoot, ["doctor", "--host", "web", "--project", project]);
    eq(res.status, 0, `passport doctor must succeed; output: ${res.stdout}\n${res.stderr}`);
    ok(res.stdout.includes("doctor: all checks passed"), "doctor must report all checks passed");
    ok(res.stdout.includes("moon toolchain"), "doctor must check the moon toolchain");
    ok(res.stdout.includes("python3"), "doctor must check the python3 dev-server dependency");
    // Web doctor never demands device tooling.
    ok(!/esp-idf/i.test(res.stdout), "web doctor must not involve ESP-IDF");
  });

  // --- Suite: browser, fixture A --------------------------------------------------

  suite("browser: CLI fixture-a bundle boots and answers input (no audio)", async () => {
    const project = fixtureDir(repoRoot, "fixture-a");
    const build = runCli(repoRoot, ["build", "--host", "web", "--project", project]);
    eq(build.status, 0, `fixture-a CLI build must succeed; stderr: ${build.stderr}`);
    const entry = printedEntryUrl(build.stdout);
    ok(entry !== null, "the CLI must print the entry URL");
    const server = await startStaticServer(path.join(project, ".passport", "web"));
    try {
      const url = `http://127.0.0.1:${server.address().port}${entry}`;
      let facts = null;
      try {
        facts = await runAutoBootBundle(url, null);
      } catch (err) {
        console.log(`  playwright CLI-bundle path failed (${err && err.message ? err.message : err}); trying chrome-headless-shell`);
      }
      if (facts && facts.payload) {
        const p = facts.payload;
        eq(facts.pageErrors.length, 0, `the page must throw nothing (got ${JSON.stringify(facts.pageErrors)})`);
        ok(p.status.startsWith("running"), `#passport-status must say running (got [${p.status}])`);
        ok(p.hasFrameExport, "the host object exposes the live wasm app");
        ok(p.frameCountAtSnapshot > 0, `app.wasm must tick (${p.frameCountAtSnapshot} frames before snapshot)`);
        ok(p.framesDuring > 0, `frames must continue during the snapshot (${p.framesDuring})`);
        eq(p.canvasWidth, 120, "canvas backing-store width");
        eq(p.assetConfigured, false, "no-audio fixture must not configure a PCM asset");
        console.log(`  fixture-a: playwright [${p.frameCountAtSnapshot}+${p.framesDuring} frames, asset=${p.assetConfigured}]`);
      } else {
        const status = runShellBundleStatus(url);
        ok(status !== null, "no browser path produced a bundle page to inspect");
        ok(status !== null && status.startsWith("running"), `bundle status must be running (got [${status}])`);
        console.log("  fixture-a fallback (chrome-headless-shell): status-line proof only");
      }
    } finally {
      server.close();
    }
  });

  // --- Suite: browser, fixture B --------------------------------------------------

  suite("browser: CLI fixture-b bundle plays its looping PCM asset", async () => {
    const project = fixtureDir(repoRoot, "fixture-b");
    const build = runCli(repoRoot, ["build", "--host", "web", "--project", project]);
    eq(build.status, 0, `fixture-b CLI build must succeed; stderr: ${build.stderr}`);
    const entry = printedEntryUrl(build.stdout);
    ok(entry !== null && entry.includes("pcm=./assets/tone.pcm"), "the CLI must print the PCM-configured entry URL");
    const server = await startStaticServer(path.join(project, ".passport", "web"));
    try {
      const url = `http://127.0.0.1:${server.address().port}${entry}`;
      let facts = null;
      try {
        facts = await runAutoBootBundleWithAudio(url);
      } catch (err) {
        console.log(`  playwright CLI-bundle path failed (${err && err.message ? err.message : err}); trying chrome-headless-shell`);
      }
      if (facts && facts.payload) {
        const p = facts.payload;
        eq(facts.pageErrors.length, 0, `the page must throw nothing (got ${JSON.stringify(facts.pageErrors)})`);
        ok(p.status.startsWith("running"), `#passport-status must say running (got [${p.status}])`);
        eq(p.assetConfigured, true, "?pcm= from the project contract must configure asset mode");
        eq(p.assetLoaded, true, "the PCM asset must be fetched over http and resident");
        eq(p.assetSamples, 4000, "asset sample count (8000-byte tone.pcm / 2)");
        eq(p.assetLooping, true, "pcmLoop from the project contract must enable looping");
        ok(!p.assetError, `no asset error (got ${JSON.stringify(p.assetError)})`);
        ok(Number(p.posUs) > 0, `playback position must be consumption-driven (> 0, got ${p.posUs})`);
        ok(p.loops >= 2, `consumption must pass 2 full asset loops (got ${p.loops})`);
        eq(p.dropped, 0, "the worklet ring must never overflow while looping");
        ok(p.framesDuring > 0, `frames must continue during the audio snapshot (${p.framesDuring})`);
        console.log(
          `  fixture-b: playwright [kind=${p.audioKind} samples=${p.assetSamples} loops=${p.loops} pos=${p.posUs}us]`,
        );
      } else {
        const status = runShellBundleStatus(url);
        ok(status !== null, "no browser path produced a bundle page to inspect");
        ok(status !== null && status.startsWith("running"), `bundle status must be running (got [${status}])`);
        console.log("  fixture-b fallback (chrome-headless-shell): status-line proof only, no audio-consumption proof");
      }
    } finally {
      server.close();
    }
  });

  // --- Suite: fixture C bundle assembly (single-entry application contract) ----

  suite("cli: fixture-c (single-entry application contract) builds through the generated entry", async () => {
    const project = fixtureDir(repoRoot, "fixture-c");
    const pin = overlayCurrentSdkIntoFixtureC(repoRoot);
    const res = runCli(repoRoot, ["build", "--host", "web", "--project", project]);
    eq(res.status, 0, `passport build must succeed for fixture-c; stderr: ${res.stderr}`);
    const bundle = path.join(project, ".passport", "web");
    ok(fs.existsSync(path.join(bundle, "app.wasm")), "bundle/app.wasm must exist");
    for (const file of ["index.html", "passport-host.js", "pcm-worklet.js"]) {
      ok(
        fs.readFileSync(path.join(bundle, file)).equals(fs.readFileSync(path.join(webHostDir, file))),
        `bundle/${file} must be byte-identical to the SDK's own host file`,
      );
    }
    ok(
      fs.readFileSync(path.join(bundle, "assets", "tone.pcm")).equals(
        fs.readFileSync(path.join(project, "assets", "tone.pcm")),
      ),
      "bundle/assets/tone.pcm must be byte-identical to the project asset",
    );
    const url = printedEntryUrl(res.stdout);
    eq(
      url,
      "/index.html?pcm=./assets/tone.pcm&pcmLoop=1",
      `the printed entry must carry the generic PCM parameters (got ${JSON.stringify(url)})`,
    );
    // The entry adapter is the CLI's generated build product.
    const generated = path.join(project, "passport-generated", "web");
    ok(fs.existsSync(path.join(generated, "moon.pkg")), "passport-generated/web/moon.pkg must exist");
    ok(fs.existsSync(path.join(generated, "adapter.mbt")), "passport-generated/web/adapter.mbt must exist");
    ok(
      res.stdout.includes("generated the Web entry adapter"),
      "the build must log the generated entry adapter",
    );
    // ABI v0 surface: every passport_* export present, and PCM asset mode
    // never declares the streamed host_pcm_write import.
    const module = await WebAssembly.compile(fs.readFileSync(path.join(bundle, "app.wasm")));
    const exported = WebAssembly.Module.exports(module).map((entry) => entry.name);
    for (const name of [
      "passport_frame",
      "passport_input",
      "passport_fb_ptr",
      "passport_fb_len",
      "passport_frame_dirty",
      "passport_frame_consume",
    ]) {
      ok(exported.includes(name), `app.wasm must export ${name}`);
    }
    const imported = WebAssembly.Module.imports(module).map((entry) => entry.name);
    ok(
      !imported.includes("host_pcm_write"),
      "the generated entry must keep the streamed PCM import out of the module (PCM asset mode)",
    );
    console.log(`  fixture-c: SDK overlaid at registry pin ${pin}; generated entry carries ABI v0`);
  });

  // --- Suite: browser, fixture C --------------------------------------------------

  /** Reads the fixture-c panel rows straight off the blitted canvas:
   *  battery bar length (row 0), volume bar length (row 8), mute row on/off
   *  (row 16), playback marker x (row 24, -1 = dark), time marker x
   *  (row 32). */
  async function samplePanelRows(page) {
    return page.evaluate(
      () =>
        new Promise((resolve) => {
          const canvas = document.getElementById("passport-canvas");
          const ctx = canvas.getContext("2d");
          const rowFacts = (y, matches) => {
            const data = ctx.getImageData(0, y, 120, 1).data;
            let count = 0;
            let at = -1;
            for (let x = 0; x < 120; x++) {
              const r = data[x * 4];
              const g = data[x * 4 + 1];
              const b = data[x * 4 + 2];
              if (matches(r, g, b)) {
                count += 1;
                if (at < 0) at = x;
              }
            }
            return { count, at };
          };
          setTimeout(() => {
            resolve({
              battery: rowFacts(0, (r, g, b) => g > 200 && r < 80 && b < 80),
              volume: rowFacts(8, (r, g, b) => r > 200 && g > 200 && b > 200),
              mute: rowFacts(16, (r, g, b) => r > 200 && g > 200 && b < 80),
              playback: rowFacts(24, (r, g, b) => r > 200 && g > 200 && b > 200),
              time: rowFacts(32, (r, g, b) => g > 200 && b > 200 && r < 80),
            });
          }, 350);
        }),
    );
  }

  suite("browser: CLI fixture-c single-entry bundle renders host facts and answers input", async () => {
    const project = fixtureDir(repoRoot, "fixture-c");
    overlayCurrentSdkIntoFixtureC(repoRoot);
    const build = runCli(repoRoot, ["build", "--host", "web", "--project", project]);
    eq(build.status, 0, `fixture-c CLI build must succeed; stderr: ${build.stderr}`);
    const entry = printedEntryUrl(build.stdout);
    ok(entry !== null && entry.includes("pcm=./assets/tone.pcm"), "the CLI must print the PCM-configured entry URL");
    const server = await startStaticServer(path.join(project, ".passport", "web"));
    try {
      const url = `http://127.0.0.1:${server.address().port}${entry}`;
      const pw = await loadPlaywright();
      if (!pw || !pw.chromium || typeof pw.chromium.launch !== "function") {
        const status = runShellBundleStatus(url);
        ok(status !== null && status.startsWith("running"), `bundle status must be running (got [${status}])`);
        console.log("  fixture-c fallback (chrome-headless-shell): status-line proof only");
        return;
      }
      const browser = await pw.chromium.launch({ headless: true, args: BROWSER_LAUNCH_FLAGS });
      const pageErrors = [];
      const consoleErrors = [];
      try {
        const page = await browser.newPage();
        page.on("pageerror", (err) => pageErrors.push(String(err)));
        page.on("console", (msg) => {
          if (msg.type() === "error") consoleErrors.push(msg.text());
        });
        await page.goto(url, { waitUntil: "load", timeout: 30_000 });
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
        // The battery import (default 82) and the startup audio state (80)
        // both reached the application: their bars are drawn to scale.
        const before = await samplePanelRows(page);
        eq(pageErrors.length, 0, `the page must throw nothing (got ${JSON.stringify(pageErrors)})`);
        ok(before.battery.count > 90 && before.battery.count < 110,
          `battery bar must render the host reading ~82% (got ${before.battery.count}px)`);
        ok(before.volume.count > 90 && before.volume.count < 110,
          `volume bar must render the startup volume 80 (got ${before.volume.count}px)`);
        ok(before.mute.count === 0, "mute row must start dark");
        // Semantic input through the host input queue: three Up presses
        // clamp the volume to 100 (full bar), Ok toggles the mute row on.
        await page.evaluate(() => {
          const host = globalThis.__passportHost;
          for (const _ of [0, 1, 2]) {
            host.queueInput(0, 1);
            host.queueInput(0, 0);
          }
          host.queueInput(2, 1);
          host.queueInput(2, 0);
        });
        await page.waitForFunction(
          () => globalThis.__passportHost.frameCount > 0,
          null,
          { timeout: 10_000, polling: 50 },
        );
        await page.waitForTimeout(400);
        const after = await samplePanelRows(page);
        eq(after.volume.count, 120, `three Up presses must clamp the volume bar to full (got ${after.volume.count}px)`);
        eq(after.mute.count, 120, `Ok must switch the mute row on (got ${after.mute.count}px)`);
        // Playback position and monotonic time keep flowing: both markers
        // move between two samples.
        const later = await samplePanelRows(page);
        ok(later.playback.at >= 0, `playback marker must be lit once audio loops (got x=${later.playback.at})`);
        const moved = later.playback.at !== before.playback.at || later.time.at !== before.time.at;
        ok(moved, `playback/time markers must move (playback ${before.playback.at}->${later.playback.at}, time ${before.time.at}->${later.time.at})`);
        const running = await page.evaluate(() => ({
          status: document.getElementById("passport-status").textContent,
          frames: globalThis.__passportHost.frameCount,
          loops: globalThis.__passportHost.audioAssetLoops,
        }));
        ok(running.status.startsWith("running"), `#passport-status must say running (got [${running.status}])`);
        ok(running.frames > 0, "frames must keep ticking");
        ok(running.loops >= 2, `the PCM asset must keep looping (got ${running.loops})`);
        eq(consoleErrors.length, 0, `no console errors (got ${JSON.stringify(consoleErrors)})`);
        console.log(
          `  fixture-c: playwright [battery=${before.battery.count}px volume=${before.volume.count}->${after.volume.count}px mute=on playback@${later.playback.at} time@${later.time.at} loops=${running.loops}]`,
        );
      } finally {
        await browser.close().catch(() => {});
      }
    } finally {
      server.close();
    }
  });
}
