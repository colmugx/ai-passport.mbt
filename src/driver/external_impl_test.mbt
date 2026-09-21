// These test-local types live OUTSIDE the driver package's own sources (they
// are compiled in the blackbox test unit) yet implement both driver traits
// and are consumed through the trait objects. That is the whole point of the
// contracts: every backend implements `Clock` and `DisplaySink` externally.

///|
/// A `Clock` with a fixed reading, proving the contract is implementable
/// outside this package.
struct FixedClock {
  value : Int
} derive(Debug)

///|
impl Clock for FixedClock with fn monotonic_ms(self) {
  self.value
}

///|
impl Clock for FixedClock with fn sleep_ms(self, ms~) {
  let _ = self
  let _ = ms
}

///|
/// A `DisplaySink` that counts frames, proving the contract is implementable
/// outside this package.
struct CountingSink {
  mut frames : Int
} derive(Debug)

///|
impl DisplaySink for CountingSink with fn present(self, frame~) {
  self.frames += 1
  let _ = frame
}

///|
/// A `DisplaySink` that copies the entire presented frame row by row,
/// proving an external backend can read every pixel of a 120x160 frame
/// through the trait seam — with no access to canvas internals. Trait
/// methods cannot raise, so copy shortfalls are recorded as state instead
/// of asserted inline.
struct RowCaptureSink {
  mut width : Int
  mut height : Int
  mut rows : Array[FixedArray[Int]]
  mut rows_complete : Bool
} derive(Debug)

///|
impl DisplaySink for RowCaptureSink with fn present(self, frame~) {
  self.width = frame.width()
  self.height = frame.height()
  self.rows_complete = true
  let rows : Array[FixedArray[Int]] = []
  for y in 0..<frame.height() {
    let row : FixedArray[Int] = FixedArray::make(frame.width(), -1)
    let copied = frame.copy_rgb565_row(y~, out=row)
    if copied != frame.width() {
      self.rows_complete = false
    }
    rows.push(row)
  }
  self.rows = rows
}

///|
test "external types implement Clock and are consumed via &Clock" {
  let clock : &@driver.Clock = FixedClock::{ value: 42, }
  clock.sleep_ms(ms=7)
  inspect(clock.monotonic_ms(), content="42")

  // The trait object can flow through helpers typed on the trait only.
  inspect(read_after_delay(clock, ms=1), content="42")
}

///|
fn read_after_delay(clock : &@driver.Clock, ms~ : Int) -> Int {
  clock.sleep_ms(ms~)
  clock.monotonic_ms()
}

///|
test "external types implement DisplaySink and are consumed via &DisplaySink" {
  let counter = CountingSink::{ frames: 0, }
  let sink : &@driver.DisplaySink = counter
  sink.present(frame=@graphics.Canvas::logical().frame_view())
  sink.present(frame=@graphics.Canvas::new(width=64, height=80).frame_view())
  inspect(counter.frames, content="2")
}

///|
test "external sink reads every row of the full 120x160 logical frame" {
  // A fresh canvas is black (RGB565 0) everywhere, so a complete capture
  // must be 160 rows of 120 zeros. Row values themselves are covered by the
  // graphics package tests against Color::to_rgb565().
  let canvas = @graphics.Canvas::logical()
  let capture = RowCaptureSink::{
    width: 0,
    height: 0,
    rows: [],
    rows_complete: true,
  }
  let sink : &@driver.DisplaySink = capture
  sink.present(frame=canvas.frame_view())

  inspect(capture.width, content="120")
  inspect(capture.height, content="160")
  inspect(capture.rows.length(), content="160")
  inspect(capture.rows_complete, content="true")
  let mut all_zero = true
  for row in capture.rows {
    if row.length() != 120 {
      all_zero = false
    }
    for i in 0..<row.length() {
      if row[i] != 0 {
        all_zero = false
      }
    }
  }
  inspect(all_zero, content="true")
}

///|
test "external sink reads two presentations of identical frames identically" {
  // Display-path determinism from the backend side: two identically built
  // canvases presented through the same external sink produce identical
  // captured frames.
  let capture = RowCaptureSink::{
    width: 0,
    height: 0,
    rows: [],
    rows_complete: true,
  }
  let sink : &@driver.DisplaySink = capture
  sink.present(frame=@graphics.Canvas::logical().frame_view())
  let first = capture.rows
  sink.present(frame=@graphics.Canvas::logical().frame_view())
  let second = capture.rows
  inspect(first.length(), content="160")
  inspect(second.length(), content="160")
  let mut identical = true
  for y in 0..<first.length() {
    for i in 0..<first[y].length() {
      if first[y][i] != second[y][i] {
        identical = false
      }
    }
  }
  inspect(identical, content="true")
}
