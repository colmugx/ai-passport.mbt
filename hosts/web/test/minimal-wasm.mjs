/**
 * minimal-wasm.mjs — deterministic emitter for the smallest wasm module that
 * satisfies the passport Host export surface while importing NOTHING. Sound
 * runtime tests use it to exercise Host-side playback commands directly.
 *
 * Module contract (frozen like the rest of the test tooling):
 *   - imports: none
 *   - memory: 4 pages (262144 B), exported as "memory" — the framebuffer at
 *     [4096, 157696) fits inside the ABI-reserved region
 *   - _start(): no-op
 *   - passport_frame(now_us): store16 the low 16 bits of now_us at byte 4096
 *     (framebuffer pixel 0) — a deterministic, observable frame side effect
 *   - passport_input(button, pressed): no-op
 *   - passport_fb_ptr() = 4096, passport_fb_len() = 153600
 *   - passport_frame_dirty() = 1 (always dirty: every tick presents, so tests
 *     can prove canvas output continues while audio runs)
 *   - passport_frame_consume(): no-op
 *
 * Byte-identical on every call; validated structurally by the node suite.
 */

/** Unsigned LEB128 for section sizes, indices, and non-negative i32.const. */
function uleb(value) {
  const out = [];
  let v = value;
  do {
    let byte = v & 0x7f;
    v >>>= 7;
    if (v !== 0) byte |= 0x80;
    out.push(byte);
  } while (v !== 0);
  return out;
}

/** Wrap payload bytes in a section: id + uleb(size) + payload. */
function section(id, payload) {
  return [id, ...uleb(payload.length), ...payload];
}

/** wasm vector: uleb(count) + items. */
function vec(items) {
  return [...uleb(items.length), ...items.flat()];
}

const END = 0x0b;
const I32_CONST = 0x41;
const LOCAL_GET = 0x20;
const I32_WRAP_I64 = 0xa7;
const I32_STORE16 = 0x3b;

const FB_PTR = 4096;
const FB_LEN = 153600;

/** Function body: empty locals vec + expression, prefixed by its byte size. */
function codeEntry(expr) {
  const body = [0x00, ...expr, END]; // 0 local groups
  return [...uleb(body.length), ...body];
}

/**
 * Build the module bytes.
 * @returns {Uint8Array} the wasm binary (deterministic).
 */
export function buildMinimalPassportWasm() {
  const header = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00];

  // Type section: 0: ()->(), 1: (i64)->(), 2: (i32,i32)->(), 3: ()->i32
  const types = vec([
    [0x60, 0x00, 0x00],
    [0x60, 0x01, 0x7e, 0x00],
    [0x60, 0x02, 0x7f, 0x7f, 0x00],
    [0x60, 0x00, 0x01, 0x7f],
  ]);

  // Function section: func index -> type index
  const funcs = vec([[0], [1], [2], [3], [3], [3], [0]]);

  // Memory section: one memory, min 4 pages, no max
  const memories = vec([[0x00, 0x04]]);

  // Export section: memory + the seven ABI exports (kind 0x02 mem, 0x00 func)
  const name = (s) => [...uleb(s.length), ...Array.from(s, (c) => c.charCodeAt(0))];
  const exp = (n, kind, idx) => [...name(n), kind, ...uleb(idx)];
  const exports = vec([
    exp("memory", 0x02, 0),
    exp("_start", 0x00, 0),
    exp("passport_frame", 0x00, 1),
    exp("passport_input", 0x00, 2),
    exp("passport_fb_ptr", 0x00, 3),
    exp("passport_fb_len", 0x00, 4),
    exp("passport_frame_dirty", 0x00, 5),
    exp("passport_frame_consume", 0x00, 6),
  ]);

  // Code section (same order as the function section):
  //  f0 _start: empty
  //  f1 passport_frame: store16 low16(now_us) at FB_PTR  — addr, then value
  //  f2 passport_input: empty
  //  f3 fb_ptr: i32.const 4096
  //  f4 fb_len: i32.const 153600
  //  f5 dirty: i32.const 1
  //  f6 consume: empty
  const i32Const = (v) => [I32_CONST, ...uleb(v)];
  const codes = vec([
    codeEntry([]),
    codeEntry([
      ...i32Const(FB_PTR), // stack: addr
      LOCAL_GET, 0x00, // now_us (i64)
      I32_WRAP_I64, // -> i32 value
      I32_STORE16, 0x00, 0x00, // align=1 (log2 0), offset=0
    ]),
    codeEntry([]),
    codeEntry(i32Const(FB_PTR)),
    codeEntry(i32Const(FB_LEN)),
    codeEntry(i32Const(1)),
    codeEntry([]),
  ]);

  const bytes = [
    ...header,
    ...section(1, types),
    ...section(3, funcs),
    ...section(5, memories),
    ...section(7, exports),
    ...section(10, codes),
  ];
  return new Uint8Array(bytes);
}
