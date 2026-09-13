///|
test "SinkProbe starts empty" {
  let probe = SinkProbe::new()
  inspect(probe.calls(), content="0")
  inspect(probe.last_width(), content="0")
  inspect(probe.last_height(), content="0")
}

///|
test "SinkProbe records count and last canvas dimensions at present time" {
  let probe = SinkProbe::new()
  let sink : &DisplaySink = probe

  // First present: the standard 120x160 logical canvas (docs/DRIVER.md).
  sink.present(canvas=@graphics.Canvas::logical())
  inspect(probe.calls(), content="1")
  inspect(probe.last_width(), content="120")
  inspect(probe.last_height(), content="160")

  // Second present: a custom 64x80 canvas overwrites the dimensions.
  sink.present(canvas=@graphics.Canvas::new(width=64, height=80))
  inspect(probe.calls(), content="2")
  inspect(probe.last_width(), content="64")
  inspect(probe.last_height(), content="80")
}
