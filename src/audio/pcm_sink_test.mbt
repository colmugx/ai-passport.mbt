// PcmSink contract tests: BufferSink recording semantics and external
// implementability of the open trait (mirrors the driver package probes).

///|
test "BufferSink records one defensive copy per write" {
  let buffer = @audio.BufferSink::new()
  let sink : &PcmSink = buffer
  let chunk : FixedArray[Int] = [7, -8, 32767, -32768]
  sink.write(samples=chunk)
  // Mutating the caller's buffer after the write must not leak into the
  // stored chunk: callers may reuse their buffers, so sinks must copy.
  chunk[0] = 999
  let stored = buffer.chunks()
  inspect(stored.length(), content="1")
  inspect(stored[0][0], content="7")
  inspect(stored[0][1], content="-8")
  inspect(stored[0][2], content="32767")
  inspect(stored[0][3], content="-32768")
}

///|
test "BufferSink chunks length matches the number of writes" {
  let buffer = @audio.BufferSink::new()
  let sink : &PcmSink = buffer
  let chunk : FixedArray[Int] = FixedArray::make(4, 0)
  sink.write(samples=chunk)
  inspect(buffer.chunks().length(), content="1")
  sink.write(samples=chunk)
  sink.write(samples=chunk)
  inspect(buffer.chunks().length(), content="3")
}

///|
test "BufferSink captures PCM through the trait" {
  let buffer = @audio.BufferSink::new()
  let sink : &PcmSink = buffer
  let chunk : FixedArray[Int] = [1200, -1200, 32767, -32768]
  sink.write(samples=chunk)
  chunk[0] = 0
  let stored = buffer.chunks()
  inspect(stored.length(), content="1")
  inspect(stored[0].length(), content="4")
  inspect(stored[0][0], content="1200")
}

///|
/// A test-local `PcmSink` proving the contract is implementable outside
/// this package and consumable as `&PcmSink`.
struct PassthroughSink {
  mut writes : Int
  mut first : Int
}

///|
impl PcmSink for PassthroughSink with fn write(
  self : PassthroughSink,
  samples~ : FixedArray[Int],
) -> Unit {
  self.writes += 1
  self.first = samples[0]
}

///|
test "external types implement PcmSink and are consumed via &PcmSink" {
  let probe = PassthroughSink::{ writes: 0, first: 0, }
  let sink : &PcmSink = probe
  sink.write(samples=[42, -42])
  sink.write(samples=[7])
  inspect(probe.writes, content="2")
  inspect(probe.first, content="7")
}
