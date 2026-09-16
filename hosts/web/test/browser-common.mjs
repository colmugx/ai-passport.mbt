/**
 * browser-common.mjs — shared browser-launch helpers for the wasm-host
 * integration suites. Extracted from run-tests.mjs so the CLI fixture
 * suites (cli-fixture-suites.mjs) drive the SAME playwright-first launch
 * paths as the core suites, with one implementation of each mechanism.
 */
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

/** Candidate npm cache roots for npx-installed packages. npm's default cache
 *  is `~/.npm` on darwin/linux (so npx installs land in `~/.npm/_npx/<hash>/
 *  node_modules/...`) and `%LocalAppData%\npm-cache` on win32; npm_config_cache
 *  (set by npm itself, e.g. in CI) wins when present. The per-entry layout
 *  under `_npx` is identical on every platform. */
function npxCacheRoots() {
  const roots = [];
  if (process.env.npm_config_cache) roots.push(process.env.npm_config_cache);
  if (process.platform === "win32") {
    roots.push(path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), "AppData", "Local"), "npm-cache"));
  } else {
    roots.push(path.join(os.homedir(), ".npm"));
  }
  return [...new Set(roots)];
}

/** Resolve playwright without any committed dependency: bare import first
 *  (NODE_PATH-style setups), then the platform's npx cache. Returns null if
 *  absent. */
export async function loadPlaywright() {
  try {
    const m = await import("playwright");
    return m.default ?? m;
  } catch {
    // fall through to the npx cache
  }
  for (const cacheRoot of npxCacheRoots()) {
    const npxCache = path.join(cacheRoot, "_npx");
    let entries = [];
    try {
      entries = fs.readdirSync(npxCache);
    } catch {
      continue;
    }
    for (const entry of entries) {
      const candidate = path.join(npxCache, entry, "node_modules", "playwright", "index.js");
      if (!fs.existsSync(candidate)) continue;
      try {
        const m = await import(pathToFileURL(candidate));
        return m.default ?? m;
      } catch {
        // try the next cache entry
      }
    }
  }
  return null;
}

/** Playwright's browser registry dir (also where `playwright install` puts
 *  the browsers): PLAYWRIGHT_BROWSERS_PATH wins unless it is "0" (playwright
 *  semantics: package-local browsers), else the per-OS default cache. */
export function playwrightBrowsersDir() {
  const env = process.env.PLAYWRIGHT_BROWSERS_PATH;
  if (env !== undefined && env !== "" && env !== "0") return env;
  switch (process.platform) {
    case "darwin":
      return path.join(os.homedir(), "Library", "Caches", "ms-playwright");
    case "win32":
      return path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), "AppData", "Local"), "ms-playwright");
    default: // linux and everything else (CI: ~/.cache/ms-playwright)
      return path.join(os.homedir(), ".cache", "ms-playwright");
  }
}

/** Locate the cached chrome-headless-shell binary (playwright cache layout). */
export function findHeadlessShell() {
  const base = playwrightBrowsersDir();
  const binName = process.platform === "win32" ? "chrome-headless-shell.exe" : "chrome-headless-shell";
  // Known per-OS download dir names (fast path; the generic scan below covers
  // any other layout).
  const knownDir = {
    darwin: "chrome-headless-shell-mac-arm64",
    win32: "chrome-headless-shell-win64",
    linux: "chrome-headless-shell-linux64",
  }[process.platform];
  let dirs = [];
  try {
    dirs = fs.readdirSync(base);
  } catch {
    return null;
  }
  for (const dir of dirs) {
    if (!dir.startsWith("chromium_headless_shell")) continue;
    const root = path.join(base, dir);
    if (knownDir) {
      const direct = path.join(root, knownDir, binName);
      if (fs.existsSync(direct)) return direct;
    }
    try {
      for (const sub of fs.readdirSync(root)) {
        const candidate = path.join(root, sub, binName);
        if (fs.existsSync(candidate)) return candidate;
      }
    } catch {
      // keep scanning
    }
  }
  return null;
}

/** Chrome flags for every launcher: the page's AudioContext must start
 *  running without a user gesture (autoplay policy), sandboxing/GPU are off
 *  for hermetic headless runs. */
export const BROWSER_LAUNCH_FLAGS = [
  "--autoplay-policy=no-user-gesture-required",
  "--no-sandbox",
  "--disable-gpu",
];

const MIME_BY_EXTENSION = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript",
  ".mjs": "text/javascript",
  ".wasm": "application/wasm",
  ".pcm": "application/octet-stream",
  ".json": "application/json",
  ".png": "image/png",
};

/** A generic static file server over one directory tree (the bundle
 *  directory contract: the server must serve whatever the bundle contains —
 *  index.html, app.wasm, passport-host.js, pcm-worklet.js and assets/ —
 *  without any per-suite route table). Query strings are ignored; only
 *  in-tree regular files are served. */
export function startStaticServer(rootDir) {
  const server = http.createServer((req, res) => {
    const urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
    if (urlPath === "/favicon.ico") {
      res.writeHead(204);
      res.end();
      return;
    }
    const relative = urlPath.replace(/^\/+/, "");
    const filePath = path.normalize(path.join(rootDir, relative));
    if (!filePath.startsWith(path.normalize(rootDir) + path.sep) && filePath !== path.normalize(rootDir)) {
      res.writeHead(403, { "content-type": "text/plain" });
      res.end("forbidden");
      return;
    }
    if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
      res.writeHead(404, { "content-type": "text/plain" });
      res.end("not found");
      return;
    }
    const type = MIME_BY_EXTENSION[path.extname(filePath)] || "application/octet-stream";
    res.writeHead(200, { "content-type": type });
    res.end(fs.readFileSync(filePath));
  });
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => resolve(server));
  });
}
