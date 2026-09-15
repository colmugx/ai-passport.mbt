///|
test "present copies every logical pixel into the framebuffer region" {
  let writes : Array[(Int, Int)] = []
  let bridge = @hostabi.HostBridge::new(
    store_u16=(addr, value) => writes.push((addr, value)),
    pcm_write=(_, _) => (),
    battery_percent=() => -1,
  )
  let canvas = @graphics.Canvas::logical()
  canvas.fill_rect(
    x=0,
    y=0,
    w=120,
    h=160,
    color=@core.Color::rgb(r=255, g=0, b=0),
  )
  let sink : &@driver.DisplaySink = bridge
  sink.present(frame=canvas.frame_view())
  // One store per logical pixel, none missing, none outside the region.
  let pixels = @core.LOGICAL_WIDTH * @core.LOGICAL_HEIGHT
  assert_eq(writes.length(), pixels)
  // Pure red quantizes to RGB565 0xF800 = 63488.
  assert_eq(writes[0], (@hostabi.FRAMEBUFFER_PTR, 63488))
  assert_eq(
    writes[pixels - 1],
    (@hostabi.FRAMEBUFFER_PTR + @hostabi.FRAMEBUFFER_LEN - 2, 63488),
  )
  // Row-major addressing with the fixed 120-pixel stride: row 1 starts at
  // pixel 120, i.e. byte offset FRAMEBUFFER_PTR + 240.
  assert_eq(
    writes[@core.LOGICAL_WIDTH],
    (@hostabi.FRAMEBUFFER_PTR + 2 * @core.LOGICAL_WIDTH, 63488),
  )
}

///|
test "present maps canvas pixel (x, y) to byte offset (y * 120 + x) * 2" {
  let writes : Array[(Int, Int)] = []
  let bridge = @hostabi.HostBridge::new(
    store_u16=(addr, value) => writes.push((addr, value)),
    pcm_write=(_, _) => (),
    battery_percent=() => -1,
  )
  let canvas = @graphics.Canvas::logical()
  canvas.clear(color=@core.Color::rgb(r=0, g=0, b=0))
  // Pure green quantizes to RGB565 0x07E0 = 2016.
  canvas.pixel(x=5, y=7, color=@core.Color::rgb(r=0, g=255, b=0))
  let sink : &@driver.DisplaySink = bridge
  sink.present(frame=canvas.frame_view())
  let idx = 7 * 120 + 5
  assert_eq(writes.length(), 19200)
  assert_eq(writes[idx], (@hostabi.FRAMEBUFFER_PTR + idx * 2, 2016))
  // Untouched pixels arrive as black.
  assert_eq(writes[0], (@hostabi.FRAMEBUFFER_PTR, 0))
  assert_eq(
    writes[19199],
    (@hostabi.FRAMEBUFFER_PTR + @hostabi.FRAMEBUFFER_LEN - 2, 0),
  )
}

///|
test "a narrower canvas copies prefix rows at the logical stride" {
  let writes : Array[(Int, Int)] = []
  let bridge = @hostabi.HostBridge::new(
    store_u16=(addr, value) => writes.push((addr, value)),
    pcm_write=(_, _) => (),
    battery_percent=() => -1,
  )
  let canvas = @graphics.Canvas::new(width=8, height=2)
  canvas.fill_rect(x=0, y=0, w=8, h=2, color=@core.Color::rgb(r=0, g=0, b=255))
  let sink : &@driver.DisplaySink = bridge
  sink.present(frame=canvas.frame_view())
  assert_eq(writes.length(), 16)
  // Row 1, column 0 still sits at the 120-pixel stride: byte offset 240.
  assert_eq(writes[8], (@hostabi.FRAMEBUFFER_PTR + 120 * 2, 31))
}

///|
test "frames larger than the logical display are clipped into the region" {
  let writes : Array[(Int, Int)] = []
  let bridge = @hostabi.HostBridge::new(
    store_u16=(addr, value) => writes.push((addr, value)),
    pcm_write=(_, _) => (),
    battery_percent=() => -1,
  )
  let canvas = @graphics.Canvas::new(width=130, height=170)
  canvas.fill_rect(
    x=0,
    y=0,
    w=130,
    h=170,
    color=@core.Color::rgb(r=255, g=255, b=255),
  )
  let sink : &@driver.DisplaySink = bridge
  sink.present(frame=canvas.frame_view())
  // Only the 120x160 prefix is copied; the framebuffer region cannot overrun.
  let pixels = @core.LOGICAL_WIDTH * @core.LOGICAL_HEIGHT
  assert_eq(writes.length(), pixels)
  let mut max_addr = 0
  for pair in writes {
    if pair.0 > max_addr {
      max_addr = pair.0
    }
  }
  assert_eq(max_addr, @hostabi.FRAMEBUFFER_PTR + @hostabi.FRAMEBUFFER_LEN - 2)
}
