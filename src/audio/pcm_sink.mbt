///|
/// Device baseline sample rate for the temporary PCM Host transport:
/// 16000 Hz signed PCM16 mono. This transport preserves the existing Host
/// behavior while the resource-backed Sound API is introduced separately.
///
/// # Example
/// ```mbt check
/// test {
///   inspect(SAMPLE_RATE, content="16000")
/// }
/// ```
pub const SAMPLE_RATE : Int = 16000

///|
/// Bounded PCM output contract, implemented by each backend (the same
/// semantics on host and device — AGENTS.md rule 3). `write` receives one
/// chunk of mono signed 16-bit samples as Int (-32768..32767); on device it
/// may block until the physical output drains. Chunk sizes are the caller's
/// choice.
///
/// Implementations must consume the samples before returning and must not
/// retain the caller's array. A sink that needs to keep the data must copy it
/// (`BufferSink` shows the defensive-copy pattern).
///
/// The trait is declared `pub(open)` so each backend implements it outside
/// this package; app-facing code only consumes `&PcmSink` values.
///
/// Verified implementation form (one `pub impl` per method; the `pub` makes
/// the impl visible outside the implementing package's main unit):
///
/// ```mbt nocheck
/// pub impl PcmSink for MySink with fn write(
///   self : MySink,
///   samples~ : FixedArray[Int],
/// ) -> Unit {
///   ...
/// }
/// ```
///
/// # Example
/// ```mbt check
/// test {
///   let buffer = BufferSink::new()
///   let sink : &PcmSink = buffer
///   let chunk : FixedArray[Int] = [0, 12000, -12000]
///   sink.write(samples=chunk)
///   let stored = buffer.chunks()
///   inspect(stored.length(), content="1")
///   inspect(stored[0][1], content="12000")
/// }
/// ```
pub(open) trait PcmSink {
  fn write(Self, samples~ : FixedArray[Int]) -> Unit
}

///|
/// Collects a defensive copy of every written chunk, in write order. Serves
/// as the test double for `&PcmSink` consumers and as backend tooling for
/// Host development previews.
///
/// # Example
/// ```mbt check
/// test {
///   let buffer = BufferSink::new()
///   let sink : &PcmSink = buffer
///   sink.write(samples=[1, -1])
///   sink.write(samples=[2, -2])
///   let stored = buffer.chunks()
///   inspect(stored.length(), content="2")
///   inspect(stored[1][0], content="2")
/// }
/// ```
pub struct BufferSink {
  priv chunks : Array[FixedArray[Int]]
}

///|
/// Creates an empty sink that has recorded no chunks yet.
///
/// # Example
/// ```mbt check
/// test {
///   let buffer = BufferSink::new()
///   inspect(buffer.chunks().length(), content="0")
/// }
/// ```
pub fn BufferSink::new() -> BufferSink {
  { chunks: [], }
}

///|
/// Records a defensive copy of `samples` as the next chunk. Mutating the
/// caller's array afterwards never changes what was stored.
///
/// # Example
/// ```mbt check
/// test {
///   let buffer = BufferSink::new()
///   let sink : &PcmSink = buffer
///   let chunk : FixedArray[Int] = [7, -8]
///   sink.write(samples=chunk)
///   chunk[0] = 999
///   // The stored copy still holds the samples as of the write call.
///   inspect(buffer.chunks()[0][0], content="7")
/// }
/// ```
pub impl PcmSink for BufferSink with fn write(
  self : BufferSink,
  samples~ : FixedArray[Int],
) -> Unit {
  self.chunks.push(FixedArray::makei(samples.length(), i => samples[i]))
}

///|
/// Every chunk recorded so far, in write order. Each element is an
/// independent copy of the samples passed to the matching `write` call; the
/// returned list is the sink's live record (further writes extend it).
///
/// # Example
/// ```mbt check
/// test {
///   let buffer = BufferSink::new()
///   let sink : &PcmSink = buffer
///   sink.write(samples=[5])
///   sink.write(samples=[6, 7])
///   let stored = buffer.chunks()
///   inspect(stored.length(), content="2")
///   inspect(stored[0].length(), content="1")
///   inspect(stored[1].length(), content="2")
/// }
/// ```
pub fn BufferSink::chunks(self : BufferSink) -> Array[FixedArray[Int]] {
  self.chunks
}
