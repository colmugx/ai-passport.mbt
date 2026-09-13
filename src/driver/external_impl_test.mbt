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
impl DisplaySink for CountingSink with fn present(self, canvas~) {
  self.frames += 1
  let _ = canvas
}

///|
test "external types implement Clock and are consumed via &Clock" {
  let clock : &Clock = FixedClock::{ value: 42, }
  clock.sleep_ms(ms=7)
  inspect(clock.monotonic_ms(), content="42")

  // The trait object can flow through helpers typed on the trait only.
  inspect(read_after_delay(clock, ms=1), content="42")
}

///|
fn read_after_delay(clock : &Clock, ms~ : Int) -> Int {
  clock.sleep_ms(ms~)
  clock.monotonic_ms()
}

///|
test "external types implement DisplaySink and are consumed via &DisplaySink" {
  let counter = CountingSink::{ frames: 0, }
  let sink : &DisplaySink = counter
  sink.present(canvas=@graphics.Canvas::logical())
  sink.present(canvas=@graphics.Canvas::new(width=64, height=80))
  inspect(counter.frames, content="2")
}
