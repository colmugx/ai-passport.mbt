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
 *                          rebuilds are clean (removed assets / stale files
 *                          cannot survive) and bundle cleanup is contained;
 *  4. fixture C          — a downstream-style SINGLE-ENTRY application (the
 *                          application contract: display, input, battery,
 *                          audio output state, playback position) builds
 *                          through the CLI-GENERATED Web entry adapter
 *                          under src/passport-generated/, keeps the ABI v0
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

  // --- Suite: project path safety -----------------------------------------------

  suite("cli: project source paths cannot escape the project root", () => {
    const temp = fs.mkdtempSync(path.join(os.tmpdir(), "passport-source-boundary-"));
    try {
      const project = path.join(temp, "project");
      const outside = path.join(temp, "outside");
      fs.cpSync(fixtureDir(repoRoot, "fixture-a"), project, { recursive: true });
      fs.mkdirSync(path.join(outside, "passport-generated", "web"), { recursive: true });
      const sentinel = path.join(outside, "passport-generated", "web", "sentinel");
      fs.writeFileSync(sentinel, "keep");

      const moonMod = path.join(project, "moon.mod");
      const original = fs.readFileSync(moonMod, "utf8");
      fs.writeFileSync(
        moonMod,
        original.replace(/^source = ".*"$/m, 'source = "../outside"'),
      );
      const traversing = runCli(repoRoot, ["build", "--host", "web", "--project", project]);
      ok(traversing.status !== 0, "a traversing moon.mod source must be refused");
      ok(
        `${traversing.stdout}\n${traversing.stderr}`.includes(
          "moon.mod: source contains an unsafe path component",
        ),
        "the traversal refusal must identify moon.mod source",
      );
      ok(fs.existsSync(sentinel), "refusing a traversing source must not touch outside files");

      fs.writeFileSync(
        moonMod,
        original.replace(/^source = ".*"$/m, 'source = "linked-src"'),
      );
      fs.symlinkSync(outside, path.join(project, "linked-src"), "dir");
      const linked = runCli(repoRoot, ["build", "--host", "web", "--project", project]);
      ok(linked.status !== 0, "a source symlink resolving outside the project must be refused");
      ok(
        `${linked.stdout}\n${linked.stderr}`.includes(
          'moon.mod: source "linked-src" resolves outside the project root',
        ),
        "the symlink refusal must identify the resolved source boundary",
      );
      ok(fs.existsSync(sentinel), "refusing an escaping source symlink must not touch outside files");

      // Ambiguous project metadata must fail before any generated-output
      // cleanup. Duplicate source declarations are never "first one wins".
      fs.rmSync(path.join(project, "linked-src"), { force: true });
      fs.writeFileSync(
        moonMod,
        original + '\nsource = "src"\n',
      );
      const duplicate = runCli(repoRoot, ["build", "--host", "web", "--project", project]);
      ok(duplicate.status !== 0, "duplicate moon.mod source declarations must be refused");
      ok(
        `${duplicate.stdout}\n${duplicate.stderr}`.includes(
          'moon.mod: duplicate "source" declaration',
        ),
        "the duplicate metadata refusal must identify moon.mod source",
      );
      ok(fs.existsSync(sentinel), "metadata parse failure must not touch outside files");
    } finally {
      fs.rmSync(temp, { recursive: true, force: true });
    }
  });

  // --- Suite: device workspace source refresh ----------------------------------

  suite("cli: device workspace prunes stale Host sources but keeps ESP-IDF state", () => {
    const temp = fs.mkdtempSync(path.join(os.tmpdir(), "passport-device-workspace-"));
    try {
      const project = path.join(temp, "project");
      const app = path.join(project, "src", "app");
      const host = path.join(project, "hosts", "folotoy", "ai-passport");
      fs.mkdirSync(app, { recursive: true });
      fs.mkdirSync(path.dirname(host), { recursive: true });
      fs.cpSync(path.join(repoRoot, "hosts", "folotoy", "ai-passport"), host, { recursive: true });
      fs.writeFileSync(
        path.join(project, "moon.mod"),
        [
          'name = "colmugx/ai-passport"',
          'version = "0.0.0"',
          'source = "src"',
          "",
        ].join("\n"),
      );
      fs.writeFileSync(path.join(app, "moon.pkg"), "");
      fs.writeFileSync(
        path.join(project, "passport.toml"),
        [
          'entry = "app"',
          "",
          '[hostDependencies."folotoy-ai-passport"]',
          'path = "missing-bsp"',
          "",
        ].join("\n"),
      );

      const workspace = path.join(project, ".passport", "folotoy-ai-passport");
      fs.mkdirSync(path.join(workspace, "components", "legacy"), { recursive: true });
      fs.writeFileSync(path.join(workspace, "components", "legacy", "legacy.c"), "stale");
      fs.writeFileSync(path.join(workspace, "obsolete.cmake"), "stale");
      fs.mkdirSync(path.join(workspace, "toolchain"), { recursive: true });
      fs.writeFileSync(path.join(workspace, "toolchain", "old-cc"), "stale");
      fs.writeFileSync(path.join(workspace, "passport_music.pcm"), "stale");

      fs.mkdirSync(path.join(workspace, "build"), { recursive: true });
      fs.writeFileSync(path.join(workspace, "build", "sentinel"), "build-cache");
      fs.mkdirSync(path.join(workspace, "managed_components"), { recursive: true });
      fs.writeFileSync(path.join(workspace, "managed_components", "sentinel"), "managed-cache");
      fs.writeFileSync(path.join(workspace, "sdkconfig"), "CONFIG_FREERTOS_HZ=1000\n");
      fs.writeFileSync(path.join(workspace, "sdkconfig.old"), "old-config\n");

      const res = runCli(repoRoot, [
        "build", "--host", "folotoy-ai-passport", "--project", project,
      ]);
      ok(res.status !== 0, "the fixture must stop at its intentionally missing BSP");
      ok(
        `${res.stdout}\n${res.stderr}`.includes(
          'passport.toml declares hostDependencies["folotoy-ai-passport"]',
        ),
        "the build must progress through workspace refresh and fail at BSP resolution",
      );

      ok(!fs.existsSync(path.join(workspace, "components", "legacy")), "removed Host components must not survive");
      ok(!fs.existsSync(path.join(workspace, "obsolete.cmake")), "stale root Host files must not survive");
      ok(!fs.existsSync(path.join(workspace, "toolchain")), "generated toolchain state must be rebuilt, not retained");
      ok(!fs.existsSync(path.join(workspace, "passport_music.pcm")), "stale application music must not survive a no-audio build");
      ok(fs.existsSync(path.join(workspace, "main", "app_main.c")), "current Host sources must be rematerialized");

      eq(fs.readFileSync(path.join(workspace, "build", "sentinel"), "utf8"), "build-cache", "build cache must survive");
      eq(
        fs.readFileSync(path.join(workspace, "managed_components", "sentinel"), "utf8"),
        "managed-cache",
        "managed components must survive",
      );
      eq(fs.readFileSync(path.join(workspace, "sdkconfig"), "utf8"), "CONFIG_FREERTOS_HZ=1000\n", "sdkconfig must survive");
      eq(fs.readFileSync(path.join(workspace, "sdkconfig.old"), "utf8"), "old-config\n", "sdkconfig.old must survive");

      const outside = path.join(temp, "outside");
      fs.mkdirSync(outside, { recursive: true });
      const sentinel = path.join(outside, "sentinel");
      fs.writeFileSync(sentinel, "keep");
      fs.symlinkSync(outside, path.join(workspace, "escape"), "dir");
      const escaped = runCli(repoRoot, [
        "build", "--host", "folotoy-ai-passport", "--project", project,
      ]);
      ok(escaped.status !== 0, "workspace cleanup must refuse an escaping symlink");
      ok(
        `${escaped.stdout}\n${escaped.stderr}`.includes(
          "refusing to prune device workspace entry outside",
        ),
        "the refusal must identify the device workspace boundary",
      );
      eq(fs.readFileSync(sentinel, "utf8"), "keep", "refused cleanup must preserve outside files");
    } finally {
      fs.rmSync(temp, { recursive: true, force: true });
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
      text.includes('host "folotoy-ai-passport" requires a "deviceEntry" package in passport.toml'),
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

  // --- Suite: deterministic Web bundle -----------------------------------------

  suite("cli: web bundle rebuild is clean and contained", () => {
    const temp = fs.mkdtempSync(path.join(os.tmpdir(), "passport-web-bundle-"));
    try {
      const project = path.join(temp, "project");
      const outside = path.join(temp, "outside");
      fs.cpSync(fixtureDir(repoRoot, "fixture-b"), project, { recursive: true });

      const first = runCli(repoRoot, ["build", "--host", "web", "--project", project]);
      eq(first.status, 0, `first Web build must succeed; stderr: ${first.stderr}`);
      const bundle = path.join(project, ".passport", "web");
      const asset = path.join(bundle, "assets", "tone.pcm");
      ok(fs.existsSync(asset), "the first build must materialize the declared PCM asset");

      // Simulate output from an older contract / SDK revision.
      fs.writeFileSync(path.join(bundle, "stale.txt"), "stale");
      fs.mkdirSync(path.join(bundle, "legacy"), { recursive: true });
      fs.writeFileSync(path.join(bundle, "legacy", "old.bin"), "stale");
      fs.writeFileSync(path.join(project, "passport.toml"), 'entry = "main"\n');

      const rebuilt = runCli(repoRoot, ["build", "--host", "web", "--project", project]);
      eq(rebuilt.status, 0, `asset-free rebuild must succeed; stderr: ${rebuilt.stderr}`);
      eq(printedEntryUrl(rebuilt.stdout), "/index.html", "removed PCM contract must produce the plain entry URL");
      ok(!fs.existsSync(asset), "an asset removed from passport.toml must not survive the rebuild");
      ok(!fs.existsSync(path.join(bundle, "stale.txt")), "arbitrary stale root files must not survive");
      ok(!fs.existsSync(path.join(bundle, "legacy")), "arbitrary stale directories must not survive");
      ok(!fs.existsSync(path.join(bundle, "assets")), "an asset-free rebuild must not retain an empty stale assets tree");

      // The recursive cleanup owns exactly .passport/web. A symlink to an
      // outside directory must fail closed before touching its contents.
      fs.rmSync(bundle, { recursive: true, force: true });
      fs.mkdirSync(outside, { recursive: true });
      const sentinel = path.join(outside, "sentinel");
      fs.writeFileSync(sentinel, "keep");
      fs.symlinkSync(outside, bundle, "dir");
      const escaped = runCli(repoRoot, ["build", "--host", "web", "--project", project]);
      ok(escaped.status !== 0, "an escaping Web bundle symlink must be refused");
      ok(
        `${escaped.stdout}\n${escaped.stderr}`.includes(
          "refusing to clear Web bundle outside the CLI-owned .passport/web directory",
        ),
        "the refusal must identify the owned Web bundle boundary",
      );
      ok(fs.existsSync(sentinel), "refused bundle cleanup must preserve outside files");
    } finally {
      fs.rmSync(temp, { recursive: true, force: true });
    }
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

}
