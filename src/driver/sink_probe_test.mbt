///|
test "SinkProbe starts empty" {
  let probe = @driver.SinkProbe::new()
  inspect(probe.calls(), content="0")
  inspect(probe.last_width(), content="0")
  inspect(probe.last_height(), content="0")
}

///|
test "SinkProbe records count and last frame dimensions at present time" {
  let probe = @driver.SinkProbe::new()
  let sink : &@driver.DisplaySink = probe

  // First present: the standard 120x160 logical frame (docs/DRIVER.md).
  sink.present(frame=@graphics.Canvas::logical().frame_view())
  inspect(probe.calls(), content="1")
  inspect(probe.last_width(), content="120")
  inspect(probe.last_height(), content="160")

  // Second present: a custom 64x80 frame overwrites the dimensions.
  sink.present(frame=@graphics.Canvas::new(width=64, height=80).frame_view())
  inspect(probe.calls(), content="2")
  inspect(probe.last_width(), content="64")
  inspect(probe.last_height(), content="80")
}
