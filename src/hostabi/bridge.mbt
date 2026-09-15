///|
/// Closure-injected adapter stack between SDK driver traits and the raw
/// Wasm host ABI v0 (internal, experimental).
///
/// `HostBridge` implements `&driver.DisplaySink`, `&audio.PcmSink`,
/// `&battery.BatterySource` and `&driver.Clock` for one app, but every raw
/// linear-memory or host-import operation is injected as a closure:
///
/// - `store_u16(addr, value)` writes one 16-bit pattern (`0..=65535`) at byte
///   address `addr` of linear memory, little-endian.
/// - `pcm_write(ptr, samples)` is the raw `host_pcm_write` import.
/// - `battery_percent()` is the raw `host_battery_percent` import.
///
/// On wasm, `new_wasm_bridge` (in the target-gated `wasm_ffi.mbt`) wires the
/// closures to the inline-WAT `store_u16` helper and the `"passport"`
/// externs. On native and js, tests inject fakes. Because all bridge logic is
/// pure integer math over those closures, the whole package compiles and is
/// unit-testable off-wasm; no MoonBit object address ever crosses the
/// boundary (AGENTS.md rule 6, work log ruling 3).
///
/// Dirty-flag state machine: `DisplaySink::present` marks the frame dirty;
/// `consume` clears it. The host blits the framebuffer between the two.
///
/// Clock semantics: `advance(now_us)` is called once per frame with the
/// `passport_frame(now_us)` argument and only ever moves the stored time
/// forward, so `Clock::monotonic_ms` never rewinds even if the host hands an
/// equal or earlier timestamp.
pub struct HostBridge {
  priv store_u16 : (Int, Int) -> Unit
  priv pcm_write : (Int, Int) -> Unit
  priv battery_percent : () -> Int
  priv mut dirty : Bool
  priv mut now_us : Int64
}

///|
/// Creates a bridge over injected raw operations.
///
/// `store_u16` receives only validated 16-bit patterns (`0..=65535`) at
/// in-region addresses; `pcm_write` receives `(PCM_STAGE_PTR, n)` with `n`
/// never exceeding `PCM_STAGE_CAPACITY_SAMPLES`; `battery_percent` returns
/// the raw wire value (`-1` = unavailable).
///
/// The bridge starts clean and at `monotonic_ms == 0`.
pub fn HostBridge::new(
  store_u16~ : (Int, Int) -> Unit,
  pcm_write~ : (Int, Int) -> Unit,
  battery_percent~ : () -> Int,
) -> HostBridge {
  { store_u16, pcm_write, battery_percent, dirty: false, now_us: 0L, }
}

///|
/// Whether a frame has been presented since the last `consume`. The wasm
/// export `passport_frame_dirty` reports this as `1`/`0`.
pub fn HostBridge::frame_dirty(self : HostBridge) -> Bool {
  self.dirty
}

///|
/// Clears the dirty flag after the host has blitted the framebuffer (the
/// wasm export `passport_frame_consume`). Calling it while clean is a no-op,
/// so the host may consume unconditionally.
pub fn HostBridge::consume(self : HostBridge) -> Unit {
  self.dirty = false
}

///|
/// Advances the frame clock to `now_us` (the `passport_frame` argument).
/// Earlier or equal timestamps never rewind the stored time, so derived
/// `Clock::monotonic_ms` values are monotonic across a run.
pub fn HostBridge::advance(self : HostBridge, now_us : Int64) -> Unit {
  if now_us > self.now_us {
    self.now_us = now_us
  }
}

///|
/// `DisplaySink` adapter: copies the presented frame into the linear-memory
/// framebuffer region, one row at a time via `FrameView::copy_rgb565_row`
/// (the only sanctioned read path — no framebuffer layout leaks into public
/// APIs, AGENTS.md rule 6), then marks the frame dirty.
///
/// Pixel `(x, y)` lands at byte address
/// `FRAMEBUFFER_PTR + (y * LOGICAL_WIDTH + x) * 2`, so the region always
/// holds the 120x160 logical frame with the ABI's fixed stride, regardless of
/// the source canvas size. A frame wider or taller than the logical display
/// is clipped to it; the region can never be overrun.
pub impl @driver.DisplaySink for HostBridge with fn present(
  self : HostBridge,
  frame~ : @graphics.FrameView,
) -> Unit {
  let height = if frame.height() < @core.LOGICAL_HEIGHT {
    frame.height()
  } else {
    @core.LOGICAL_HEIGHT
  }
  let row : FixedArray[Int] = FixedArray::make(@core.LOGICAL_WIDTH, 0)
  for y in 0..<height {
    let n = frame.copy_rgb565_row(y~, out=row)
    for i in 0..<n {
      (self.store_u16)(
        FRAMEBUFFER_PTR + (y * @core.LOGICAL_WIDTH + i) * 2,
        row[i],
      )
    }
  }
  self.dirty = true
}

///|
/// `PcmSink` adapter: clamps and encodes each sample with `pcm16_le_bits`,
/// stages at most `PCM_STAGE_CAPACITY_SAMPLES` into the PCM region (pixel
/// offset `PCM_STAGE_PTR + 2 * i`), then flushes the region with one
/// `host_pcm_write(PCM_STAGE_PTR, n)` call per chunk. Larger writes are
/// chunked in order — the host sees the sample stream intact across calls.
/// An empty write stages nothing and performs no host call.
pub impl @audio.PcmSink for HostBridge with fn write(
  self : HostBridge,
  samples~ : FixedArray[Int],
) -> Unit {
  let total = samples.length()
  for base = 0; base < total; {
    let n = if total - base < PCM_STAGE_CAPACITY_SAMPLES {
      total - base
    } else {
      PCM_STAGE_CAPACITY_SAMPLES
    }
    for i in 0..<n {
      (self.store_u16)(PCM_STAGE_PTR + i * 2, pcm16_le_bits(samples[base + i]))
    }
    (self.pcm_write)(PCM_STAGE_PTR, n)
    continue base + n
  }
}

///|
/// `BatterySource` adapter over the raw `host_battery_percent` import: the
/// wire sentinel `-1` (any negative value, defensively) maps to `None`
/// (reading unavailable — callers degrade, never crash); `0..=100` passes
/// through as `Some`.
pub impl @battery.BatterySource for HostBridge with fn percent(
  self : HostBridge,
) -> Int? {
  let raw = (self.battery_percent)()
  if raw < 0 {
    None
  } else {
    Some(raw)
  }
}

///|
/// Millivolts have no ABI v0 import, so this source never offers them.
pub impl @battery.BatterySource for HostBridge with fn millivolts(
  self : HostBridge,
) -> Int? {
  let _ = self
  None
}

///|
/// `Clock` adapter: reports the latest `advance(now_us)` frame timestamp as
/// whole milliseconds (`now_us / 1000`, integer division). Values fit `Int`
/// for any realistic run length; like every `Clock`, consumers must compare
/// deltas, never absolute values.
pub impl @driver.Clock for HostBridge with fn monotonic_ms(self : HostBridge) -> Int {
  (self.now_us / 1000L).to_int()
}

///|
/// Sleep is not part of ABI v0: the host paces frames via `passport_frame`.
/// This is a deliberate no-op rather than a busy wait.
pub impl @driver.Clock for HostBridge with fn sleep_ms(
  self : HostBridge,
  ms~ : Int,
) -> Unit {
  let _ = self
  let _ = ms
}
