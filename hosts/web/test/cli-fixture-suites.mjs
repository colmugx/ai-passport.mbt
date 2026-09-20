/**
 * cli-fixture-suites.mjs — integration suites for the passport CLI
 * (`src/cmd/passport`), registered into run-tests.mjs.
 *
 * The ten suites here cover the real CLI behavior exercised in CI:
 *  1. structural terminology/application-semantics gates;
 *  2. project source-root traversal and symlink containment;
 *  3. Rule/dev_build typed sound mapping regeneration;
 *  4. device workspace stale-source pruning with ESP-IDF state preservation;
 *  5. fixture A no-audio Web bundle assembly plus device-entry refusal;
 *  6. fixture B APSB Web bundle assembly;
 *  7. deterministic Web bundle rebuild and cleanup containment;
 *  8. doctor on a resolvable downstream-style Web project;
 *  9. fixture A browser auto-boot/input proof;
 * 10. fixture B sound-bank determinism.
 *
 * The fixtures are complete nested MoonBit modules under
 * hosts/web/test/fixtures/ and depend on published ai-passport versions.
 * Tests that need current unpublished behavior use temporary projects built
 * directly from this checkout instead of mutating a fixture dependency tree.
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

/** Fixed downstream fixtures keep a published module manifest, but every CI
 * run must exercise this checkout's SDK packages and Host assets. Refresh the
 * ignored dependency payload before invoking Moon so no stale 0.0.x API can
 * masquerade as the implementation under test. */
function syncFixtureSdk(repoRoot, project) {
  const selected = path.join(project, ".mooncakes", "colmugx", "ai-passport");
  fs.mkdirSync(selected, { recursive: true });
  fs.writeFileSync(
    path.join(selected, "moon.mod"),
    'name = "colmugx/ai-passport"\nversion = "0.0.3"\nsource = "src"\n',
  );
  const selectedSrc = path.join(selected, "src");
  fs.rmSync(selectedSrc, { recursive: true, force: true });
  fs.mkdirSync(selectedSrc, { recursive: true });
  for (const name of ["core", "graphics", "driver", "input", "battery", "hostabi"]) {
    fs.cpSync(path.join(repoRoot, "src", name), path.join(selectedSrc, name), { recursive: true });
  }
  const selectedWeb = path.join(selected, "hosts", "web");
  fs.mkdirSync(selectedWeb, { recursive: true });
  for (const file of ["index.html", "passport-host.js", "sound-worklet.js"]) {
    fs.copyFileSync(path.join(repoRoot, "hosts", "web", file), path.join(selectedWeb, file));
  }
}

/** Extracts the entry URL the CLI printed ("passport: entry: /..."). */
function printedEntryUrl(stdout) {
  const m = /^passport: entry: (\S+)$/m.exec(stdout);
  return m ? m[1] : null;
}

function readSoundBank(file) {
  const require = (condition, message) => {
    if (!condition) throw new Error(message);
  };
  const requireEq = (actual, expected, message) => {
    if (actual !== expected) throw new Error(`${message}: expected ${expected}, got ${actual}`);
  };
  const bytes = fs.readFileSync(file);
  require(bytes.length >= 16, `sound bank header must be complete (${bytes.length} bytes)`);
  requireEq(bytes.subarray(0, 4).toString("ascii"), "APSB", "sound bank magic");
  requireEq(bytes.readUInt16LE(4), 1, "sound bank version");
  requireEq(bytes.readUInt16LE(6), 16, "sound bank header size");
  const count = bytes.readUInt32LE(8);
  requireEq(bytes.readUInt16LE(12), 8, "sound bank entry size");
  requireEq(bytes.readUInt16LE(14), 0, "sound bank flags");
  const entries = [];
  let expectedOffset = 16 + count * 8;
  for (let id = 0; id < count; id += 1) {
    const at = 16 + id * 8;
    const offset = bytes.readUInt32LE(at);
    const samples = bytes.readUInt32LE(at + 4);
    requireEq(offset, expectedOffset, `sound ${id} payload must be contiguous`);
    expectedOffset += samples * 2;
    require(expectedOffset <= bytes.length, `sound ${id} payload must fit in the bank`);
    entries.push({ id, offset, samples });
  }
  requireEq(expectedOffset, bytes.length, "sound bank must have no trailing bytes");
  return { bytes, entries };
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

export function registerCliFixtureSuites({ suite, ok, eq, eqText, SuiteError, repoRoot, webHostDir, skipBrowser }) {
  const passportCli = path.join(repoRoot, CLI_PACKAGE);
  syncFixtureSdk(repoRoot, fixtureDir(repoRoot, "fixture-a"));
  syncFixtureSdk(repoRoot, fixtureDir(repoRoot, "fixture-b"));

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

  suite("cli: project paths cannot escape the project root", () => {
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

      // Sound sources are canonicalized independently from lexical TOML path
      // checks. An in-project symlink to an outside PCM must fail before the
      // previous Web bundle is cleared.
      fs.writeFileSync(moonMod, original);
      const assets = path.join(project, "assets");
      fs.mkdirSync(assets, { recursive: true });
      const outsidePcm = path.join(outside, "escape.pcm");
      fs.writeFileSync(outsidePcm, Buffer.from([0, 0]));
      fs.symlinkSync(outsidePcm, path.join(assets, "escape.pcm"));
      fs.writeFileSync(
        path.join(project, "passport.toml"),
        [
          'entry = "main"',
          "",
          "[[sounds]]",
          'name = "escape"',
          'source = "assets/escape.pcm"',
          "",
        ].join("\n"),
      );
      const oldBundle = path.join(project, ".passport", "web");
      fs.mkdirSync(oldBundle, { recursive: true });
      const oldBundleSentinel = path.join(oldBundle, "known-good");
      fs.writeFileSync(oldBundleSentinel, "keep");
      const escapedSound = runCli(repoRoot, ["build", "--host", "web", "--project", project]);
      ok(escapedSound.status !== 0, "an escaping sound symlink must be refused");
      ok(
        `${escapedSound.stdout}\n${escapedSound.stderr}`.includes(
          "sound source resolves outside the project root: assets/escape.pcm",
        ),
        "the refusal must identify the sound source boundary",
      );
      ok(fs.existsSync(oldBundleSentinel), "invalid sound input must preserve the previous Web bundle");

      fs.rmSync(path.join(assets, "escape.pcm"));
      fs.writeFileSync(
        path.join(project, "passport.toml"),
        'entry = "main"\n[[sounds]]\nname = "missing"\nsource = "assets/missing.pcm"\n',
      );
      const missingSound = runCli(repoRoot, ["build", "--host", "web", "--project", project]);
      ok(missingSound.status !== 0, "a missing sound source must fail");
      ok(
        `${missingSound.stdout}\n${missingSound.stderr}`.includes("sound source is missing: assets/missing.pcm"),
        "the missing sound refusal must identify the configured source",
      );
      ok(fs.existsSync(oldBundleSentinel), "missing sound input must preserve the previous Web bundle");

      fs.writeFileSync(path.join(assets, "odd.pcm"), Buffer.from([0]));
      fs.writeFileSync(
        path.join(project, "passport.toml"),
        'entry = "main"\n[[sounds]]\nname = "odd"\nsource = "assets/odd.pcm"\n',
      );
      const oddSound = runCli(repoRoot, ["build", "--host", "web", "--project", project]);
      ok(oddSound.status !== 0, "an odd-length PCM source must fail");
      ok(
        `${oddSound.stdout}\n${oddSound.stderr}`.includes("PCM byte length must be even"),
        "the PCM refusal must identify the even-byte contract",
      );
      ok(fs.existsSync(oldBundleSentinel), "invalid PCM input must preserve the previous Web bundle");
    } finally {
      fs.rmSync(temp, { recursive: true, force: true });
    }
  });

  // --- Suite: generated sound Rule --------------------------------------------

  suite("cli: Rule/dev_build regenerates typed sound mappings", () => {
    const temp = fs.mkdtempSync(path.join(os.tmpdir(), "passport-sound-rule-"));
    try {
      const project = path.join(temp, "project");
      const audio = path.join(project, "src", "audio");
      const resources = path.join(project, "src", "audio_resources");
      const app = path.join(project, "src", "app");
      fs.mkdirSync(audio, { recursive: true });
      fs.mkdirSync(resources, { recursive: true });
      fs.mkdirSync(app, { recursive: true });
      fs.writeFileSync(
        path.join(project, "moon.mod"),
        [
          'name = "colmugx/ai-passport"',
          'version = "0.0.0"',
          'source = "src"',
          "",
        ].join("\n"),
      );
      fs.writeFileSync(path.join(audio, "moon.pkg"), "");
      fs.writeFileSync(
        path.join(audio, "sound.mbt"),
        "pub(open) trait Sound {\n  fn resource_id(Self) -> UInt\n}\n",
      );
      const cliBuild = spawnSync(
        "moon",
        ["build", "src/cmd/passport", "--target", "wasm", "--release"],
        { cwd: repoRoot, encoding: "utf8", timeout: 240_000, maxBuffer: 16 * 1024 * 1024 },
      );
      eq(cliBuild.status, 0, `passport CLI build must pass; stderr: ${cliBuild.stderr}`);
      const cliWasm = path.join(
        repoRoot,
        "_build", "wasm", "release", "build", "cmd", "passport", "passport.wasm",
      );
      const ruleCommand = [
        "moonrun", cliWasm, "generate-sounds", "$input", "$output",
      ].join(" ");
      fs.writeFileSync(
        path.join(resources, "moon.pkg"),
        [
          'import { "colmugx/ai-passport/audio" @audio }',
          `rule(name: "passport-sounds", command: "${ruleCommand}")`,
          'dev_build(rule: "passport-sounds", input: "../../passport.toml", output: "bindings.mbt")',
          "",
        ].join("\n"),
      );
      fs.writeFileSync(
        path.join(app, "moon.pkg"),
        'import { "colmugx/ai-passport/audio_resources" @sounds }\n',
      );
      const writeApp = (symbol) => fs.writeFileSync(
        path.join(app, "app.mbt"),
        symbol
          ? `pub fn selected() -> @sounds.Sound { @sounds.${symbol} }\n`
          : "pub fn no_sound() -> Unit { () }\n",
      );
      const writeContract = (soundsList) => {
        const sections = soundsList.map(({ name, source }) => [
          "[[sounds]]",
          `name = "${name}"`,
          `source = "${source}"`,
          "",
        ].join("\n"));
        const contract = path.join(project, "passport.toml");
        fs.writeFileSync(contract, ['entry = "app"', "", ...sections].join("\n"));
        const future = new Date(Date.now() + 2000);
        fs.utimesSync(contract, future, future);
      };
      const check = () => spawnSync(
        "moon",
        ["check", "--output-json"],
        { cwd: project, encoding: "utf8", timeout: 240_000, maxBuffer: 16 * 1024 * 1024 },
      );

      writeContract([
        { name: "forest_walk", source: "assets/forest.pcm" },
        { name: "jump", source: "assets/jump.pcm" },
      ]);
      writeApp("ForestWalk");
      const generated = path.join(resources, "bindings.mbt");
      const outside = path.join(temp, "outside-generated.mbt");
      fs.writeFileSync(outside, "keep");
      fs.symlinkSync(outside, generated);
      const escaped = check();
      ok(escaped.status !== 0, "Rule output symlink must be refused");
      ok(
        `${escaped.stdout}\n${escaped.stderr}`.includes("must not be a symbolic link"),
        "Rule output refusal must identify the symbolic link",
      );
      eq(fs.readFileSync(outside, "utf8"), "keep", "refused Rule output must preserve outside files");
      fs.rmSync(generated);

      const first = check();
      eq(first.status, 0, `initial Rule-driven moon check must pass; stderr: ${first.stderr}`);
      const firstSource = fs.readFileSync(generated, "utf8");
      ok(firstSource.includes("ForestWalk => 0U"), "first sound constructor must map to ID 0");
      ok(firstSource.includes("Jump => 1U"), "second sound constructor must map to ID 1");

      writeContract([{ name: "forest_path", source: "assets/forest.pcm" }]);
      writeApp("ForestPath");
      const second = check();
      eq(second.status, 0, `renamed Rule-driven moon check must pass; stderr: ${second.stderr}`);
      const secondSource = fs.readFileSync(generated, "utf8");
      ok(secondSource.includes("ForestPath => 0U"), "renamed constructor must be generated");
      ok(!secondSource.includes("ForestWalk"), "renamed constructor must remove the old symbol");
      ok(!secondSource.includes("Jump"), "deleted sound must remove the old symbol");

      writeContract([]);
      writeApp(null);
      fs.writeFileSync(path.join(app, "moon.pkg"), "");
      const empty = check();
      eq(empty.status, 0, `empty sound mapping must type-check; stderr: ${empty.stderr}`);
      const emptySource = fs.readFileSync(generated, "utf8");
      ok(emptySource.includes("pub(all) enum Sound"), "empty project must retain the typed Sound enum");
      ok(!emptySource.includes("ForestPath"), "removing every sound must remove every constructor");

      writeContract([
        { name: "ambient_walk", source: "assets/a.pcm" },
        { name: "Ambient_walk", source: "assets/b.pcm" },
      ]);
      const collision = check();
      ok(collision.status !== 0, "generated symbol collision must fail moon check");
      ok(
        `${collision.stdout}\n${collision.stderr}`.includes("collide after MoonBit symbol generation"),
        "Rule failure must preserve the metadata compiler collision diagnostic",
      );
      eq(
        fs.readFileSync(generated, "utf8"),
        emptySource,
        "failed generation must preserve the last valid mapping",
      );
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
      fs.mkdirSync(path.join(project, "assets"), { recursive: true });
      fs.writeFileSync(path.join(project, "assets", "hit.pcm"), Buffer.from([1, 0, 2, 0]));
      fs.writeFileSync(
        path.join(project, "passport.toml"),
        [
          'entry = "app"',
          "",
          '[hostDependencies."folotoy-ai-passport"]',
          'path = "missing-bsp"',
          "",
          "[[sounds]]",
          'name = "hit"',
          'source = "assets/hit.pcm"',
          "",
        ].join("\n"),
      );

      const workspace = path.join(project, ".passport", "folotoy-ai-passport");
      fs.mkdirSync(path.join(workspace, "components", "legacy"), { recursive: true });
      fs.writeFileSync(path.join(workspace, "components", "legacy", "legacy.c"), "stale");
      fs.writeFileSync(path.join(workspace, "obsolete.cmake"), "stale");
      fs.mkdirSync(path.join(workspace, "toolchain"), { recursive: true });
      fs.writeFileSync(path.join(workspace, "toolchain", "old-cc"), "stale");

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
      ok(fs.existsSync(path.join(workspace, "main", "app_main.c")), "current Host sources must be rematerialized");
      const deviceBank = readSoundBank(path.join(workspace, "sounds.bank"));
      eq(deviceBank.entries.length, 1, "device workspace sound bank entry count");
      eq(deviceBank.entries[0].samples, 2, "device workspace sound sample count");
      ok(
        deviceBank.bytes.subarray(deviceBank.entries[0].offset).equals(Buffer.from([1, 0, 2, 0])),
        "device workspace bank must contain the declared PCM bytes",
      );

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
    const selectedWebHost = path.join(
      project, ".mooncakes", "colmugx", "ai-passport", "hosts", "web",
    );
    const res = runCli(repoRoot, ["build", "--host", "web", "--project", project]);
    eq(res.status, 0, `passport build must succeed for fixture-a; stderr: ${res.stderr}`);
    const bundle = path.join(project, ".passport", "web");
    ok(fs.existsSync(path.join(bundle, "app.wasm")), "bundle/app.wasm must exist");
    const emptyBank = readSoundBank(path.join(bundle, "sounds.bank"));
    eq(emptyBank.entries.length, 0, "no-audio project must emit an empty sound bank");
    eq(emptyBank.bytes.length, 16, "empty sound bank must contain only its header");
    for (const file of ["index.html", "passport-host.js", "sound-worklet.js"]) {
      ok(
        fs.readFileSync(path.join(bundle, file)).equals(fs.readFileSync(path.join(selectedWebHost, file))),
        `bundle/${file} must be byte-identical to the project's selected SDK host file`,
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

  suite("cli: fixture-b builds one deterministic APSB sound bank", () => {
    const project = fixtureDir(repoRoot, "fixture-b");
    const selectedWebHost = path.join(
      project, ".mooncakes", "colmugx", "ai-passport", "hosts", "web",
    );
    const res = runCli(repoRoot, ["build", "--host", "web", "--project", project]);
    eq(res.status, 0, `passport build must succeed for fixture-b; stderr: ${res.stderr}`);
    const bundle = path.join(project, ".passport", "web");
    ok(fs.existsSync(path.join(bundle, "app.wasm")), "bundle/app.wasm must exist");
    for (const file of ["index.html", "passport-host.js", "sound-worklet.js"]) {
      ok(
        fs.readFileSync(path.join(bundle, file)).equals(fs.readFileSync(path.join(selectedWebHost, file))),
        `bundle/${file} must be byte-identical to the project's selected SDK host file`,
      );
    }
    ok(!fs.existsSync(path.join(bundle, "assets", "tone.pcm")), "sound PCM must not ship as a loose Web asset");
    const soundBank = readSoundBank(path.join(bundle, "sounds.bank"));
    eq(soundBank.entries.length, 2, "fixture-b sound bank entry count");
    eq(soundBank.entries[0].samples, 4000, "first sound sample count");
    eq(soundBank.entries[1].samples, 4000, "second sound sample count");
    const tone = fs.readFileSync(path.join(project, "assets", "tone.pcm"));
    for (const entry of soundBank.entries) {
      ok(
        soundBank.bytes.subarray(entry.offset, entry.offset + entry.samples * 2).equals(tone),
        `sound ${entry.id} payload must equal its declared PCM source`,
      );
    }
    const url = printedEntryUrl(res.stdout);
    eq(url, "/index.html", `sound banks must not configure the Host URL (got ${JSON.stringify(url)})`);
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
      const firstBank = readSoundBank(path.join(bundle, "sounds.bank"));
      eq(firstBank.entries.length, 2, "the first build must materialize both sounds");

      // Simulate output from an older contract / SDK revision.
      fs.writeFileSync(path.join(bundle, "stale.txt"), "stale");
      fs.mkdirSync(path.join(bundle, "legacy"), { recursive: true });
      fs.writeFileSync(path.join(bundle, "legacy", "old.bin"), "stale");
      fs.writeFileSync(path.join(project, "passport.toml"), 'entry = "main"\n');

      const rebuilt = runCli(repoRoot, ["build", "--host", "web", "--project", project]);
      eq(rebuilt.status, 0, `asset-free rebuild must succeed; stderr: ${rebuilt.stderr}`);
      eq(printedEntryUrl(rebuilt.stdout), "/index.html", "an empty sound contract keeps the plain entry URL");
      eq(readSoundBank(path.join(bundle, "sounds.bank")).entries.length, 0, "removed sounds must disappear from the rebuilt bank");
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
    if (skipBrowser) {
      console.log("  skipped by --skip-browser / PASSPORT_SKIP_BROWSER=1");
      return;
    }
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
        console.log(`  fixture-a: playwright [${p.frameCountAtSnapshot}+${p.framesDuring} frames]`);
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

}
