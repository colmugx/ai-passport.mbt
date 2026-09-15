///|
test "pcm write clamps overshoot and stages two's-complement LE patterns" {
  let staged : Array[(Int, Int)] = []
  let calls : Array[Int] = []
  let bridge = @hostabi.HostBridge::new(
    store_u16=(addr, value) => staged.push((addr, value)),
    pcm_write=(_, n) => calls.push(n),
    battery_percent=() => -1,
  )
  let sink : &@audio.PcmSink = bridge
  let samples : FixedArray[Int] = [40000, -40000, 32767, -32768, 0, 1, -1]
  sink.write(samples~)
  // One flush call for one chunk within capacity, at the staging pointer.
  assert_eq(calls.length(), 1)
  assert_eq(calls[0], 7)
  // 40000 -> 32767; -40000 -> -32768 -> 0x8000; -1 -> 0xFFFF.
  let expected : Array[Int] = [32767, 32768, 32767, 32768, 0, 1, 65535]
  for i in 0..<expected.length() {
    assert_eq(staged[i], (@hostabi.PCM_STAGE_PTR + i * 2, expected[i]))
  }
}

///|
test "extreme overshoot saturates at the signed 16-bit ends" {
  let staged : Array[(Int, Int)] = []
  let calls : Array[Int] = []
  let bridge = @hostabi.HostBridge::new(
    store_u16=(addr, value) => staged.push((addr, value)),
    pcm_write=(_, n) => calls.push(n),
    battery_percent=() => -1,
  )
  let sink : &@audio.PcmSink = bridge
  let samples : FixedArray[Int] = [2147483647, -2147483648, 100000, -100000]
  sink.write(samples~)
  assert_eq(calls, [4])
  assert_eq(staged[0], (@hostabi.PCM_STAGE_PTR, 32767))
  assert_eq(staged[1], (@hostabi.PCM_STAGE_PTR + 2, 32768))
  assert_eq(staged[2], (@hostabi.PCM_STAGE_PTR + 4, 32767))
  assert_eq(staged[3], (@hostabi.PCM_STAGE_PTR + 6, 32768))
}

///|
test "in-range endpoint samples pass through bit-exact" {
  let staged : Array[(Int, Int)] = []
  let bridge = @hostabi.HostBridge::new(
    store_u16=(addr, value) => staged.push((addr, value)),
    pcm_write=(_, _) => (),
    battery_percent=() => -1,
  )
  let sink : &@audio.PcmSink = bridge
  let samples : FixedArray[Int] = [32767, -32768]
  sink.write(samples~)
  assert_eq(staged[0], (@hostabi.PCM_STAGE_PTR, 32767))
  assert_eq(staged[1], (@hostabi.PCM_STAGE_PTR + 2, 32768))
}

///|
test "an empty write stages nothing and performs no host call" {
  let staged : Array[(Int, Int)] = []
  let calls : Array[Int] = []
  let bridge = @hostabi.HostBridge::new(
    store_u16=(addr, value) => staged.push((addr, value)),
    pcm_write=(_, n) => calls.push(n),
    battery_percent=() => -1,
  )
  let sink : &@audio.PcmSink = bridge
  sink.write(samples=FixedArray::make(0, 0))
  assert_eq(staged.length(), 0)
  assert_eq(calls.length(), 0)
}

///|
test "8191 samples stay in one short chunk" {
  let calls : Array[Int] = []
  let bridge = @hostabi.HostBridge::new(
    store_u16=(_, _) => (),
    pcm_write=(_, n) => calls.push(n),
    battery_percent=() => -1,
  )
  let sink : &@audio.PcmSink = bridge
  sink.write(
    samples=FixedArray::make(@hostabi.PCM_STAGE_CAPACITY_SAMPLES - 1, 7),
  )
  assert_eq(calls, [@hostabi.PCM_STAGE_CAPACITY_SAMPLES - 1])
}

///|
test "8192 samples fill exactly one full-capacity chunk" {
  let staged : Array[(Int, Int)] = []
  let calls : Array[Int] = []
  let bridge = @hostabi.HostBridge::new(
    store_u16=(addr, value) => staged.push((addr, value)),
    pcm_write=(_, n) => calls.push(n),
    battery_percent=() => -1,
  )
  let sink : &@audio.PcmSink = bridge
  sink.write(samples=FixedArray::make(@hostabi.PCM_STAGE_CAPACITY_SAMPLES, -3))
  assert_eq(calls, [@hostabi.PCM_STAGE_CAPACITY_SAMPLES])
  // Every sample of the capacity was staged before the single flush.
  assert_eq(staged.length(), @hostabi.PCM_STAGE_CAPACITY_SAMPLES)
  let last_addr = @hostabi.PCM_STAGE_PTR +
    (@hostabi.PCM_STAGE_CAPACITY_SAMPLES - 1) * 2
  assert_eq(staged[@hostabi.PCM_STAGE_CAPACITY_SAMPLES - 1], (last_addr, 65533))
}

///|
test "8193 samples split into an in-order full chunk plus a one-sample tail" {
  let staged : Array[(Int, Int)] = []
  let calls : Array[Int] = []
  let bridge = @hostabi.HostBridge::new(
    store_u16=(addr, value) => staged.push((addr, value)),
    pcm_write=(_, n) => calls.push(n),
    battery_percent=() => -1,
  )
  let sink : &@audio.PcmSink = bridge
  let total = @hostabi.PCM_STAGE_CAPACITY_SAMPLES + 1
  let samples = FixedArray::makei(total, i => i % 2001 - 1000)
  sink.write(samples~)
  // Full chunk first, then the tail chunk, both from the staging pointer.
  assert_eq(calls, [@hostabi.PCM_STAGE_CAPACITY_SAMPLES, 1])
  assert_eq(staged.length(), total)
  // Each staged pattern is the source sample in stream order; the tail chunk
  // restarts staging at PCM_STAGE_PTR.
  for i in 0..<total {
    assert_eq(staged[i].0, @hostabi.PCM_STAGE_PTR + i % 8192 * 2)
    assert_eq(staged[i].1, @hostabi.pcm16_le_bits(samples[i]))
  }
}

///|
test "successive writes stage and flush in stream order" {
  let staged : Array[(Int, Int)] = []
  let calls : Array[Int] = []
  let bridge = @hostabi.HostBridge::new(
    store_u16=(addr, value) => staged.push((addr, value)),
    pcm_write=(_, n) => calls.push(n),
    battery_percent=() => -1,
  )
  let sink : &@audio.PcmSink = bridge
  sink.write(samples=[1, 2, 3])
  sink.write(samples=[4])
  assert_eq(calls, [3, 1])
  assert_eq(staged, [
    (@hostabi.PCM_STAGE_PTR, 1),
    (@hostabi.PCM_STAGE_PTR + 2, 2),
    (@hostabi.PCM_STAGE_PTR + 4, 3),
    (@hostabi.PCM_STAGE_PTR, 4),
  ])
}
