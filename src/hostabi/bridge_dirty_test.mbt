///|
test "a fresh bridge is clean" {
  let bridge = @hostabi.HostBridge::new(store_u16=(_, _) => (), battery_percent=() => {
    -1
  })
  assert_false(bridge.frame_dirty())
}

///|
test "present marks the bridge dirty" {
  let bridge = @hostabi.HostBridge::new(store_u16=(_, _) => (), battery_percent=() => {
    -1
  })
  let canvas = @graphics.Canvas::new(width=4, height=4)
  canvas.fill_rect(x=0, y=0, w=4, h=4, color=@core.Color::rgb(r=0, g=0, b=0))
  let sink : &@driver.DisplaySink = bridge
  sink.present(frame=canvas.frame_view())
  assert_true(bridge.frame_dirty())
}

///|
test "consume clears the dirty flag and is idempotent" {
  let bridge = @hostabi.HostBridge::new(store_u16=(_, _) => (), battery_percent=() => {
    -1
  })
  let canvas = @graphics.Canvas::new(width=4, height=4)
  canvas.fill_rect(x=0, y=0, w=4, h=4, color=@core.Color::rgb(r=0, g=0, b=0))
  let sink : &@driver.DisplaySink = bridge
  sink.present(frame=canvas.frame_view())
  bridge.consume()
  assert_false(bridge.frame_dirty())
  // Consuming while clean stays a no-op (the host may consume unconditionally).
  bridge.consume()
  assert_false(bridge.frame_dirty())
}

///|
test "a second present re-marks the unconsumed bridge dirty" {
  let bridge = @hostabi.HostBridge::new(store_u16=(_, _) => (), battery_percent=() => {
    -1
  })
  let canvas = @graphics.Canvas::new(width=2, height=2)
  canvas.fill_rect(x=0, y=0, w=2, h=2, color=@core.Color::rgb(r=0, g=0, b=0))
  let sink : &@driver.DisplaySink = bridge
  sink.present(frame=canvas.frame_view())
  bridge.consume()
  sink.present(frame=canvas.frame_view())
  assert_true(bridge.frame_dirty())
}
