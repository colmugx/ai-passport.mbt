// PcmSink contract tests: BufferSink recording semantics and external
// implementability of the open trait (mirrors the driver package probes).

///|
test "BufferSink records one defensive copy per write" {
  let buffer = @audio.BufferSink::new()
  let sink : &PcmSink = buffer
  let chunk : FixedArray[Int] = [7, -8, 32767, -32768]
  sink.write(samples=chunk)
  // Mutating the caller's buffer after the write must not leak into the
  // stored chunk: render reuses its output buffers, so sinks must copy.
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
test "BufferSink captures render output through the trait" {
  let synth = @audio.Synth::new()
  synth.trigger(voice=0, on=note(69, @music.Pulse12), gate_samples=256)
  let buffer = @audio.BufferSink::new()
  let sink : &PcmSink = buffer
  let chunk : FixedArray[Int] = FixedArray::make(256, 0)
  synth.render(out=chunk)
  sink.write(samples=chunk)
  chunk[0] = 0
  let stored = buffer.chunks()
  inspect(stored.length(), content="1")
  inspect(stored[0].length(), content="256")
  // The copied chunk still holds the rendered celesta pluck.
  inspect(stored[0][255] != 0, content="true")
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
