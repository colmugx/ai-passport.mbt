///|
test "the no-audio application exposes no audio state" {
  let app = @app.passport_main()
  debug_inspect(app.audio_output(), content="None")
  app.update({
    now_us: 1_000L,
    presentation_lead_us: 100_000L,
  })
  app.button(@input.Ok, true)
  let frame = app.render(None)
  assert_eq(frame.width(), @core.LOGICAL_WIDTH)
  assert_eq(frame.height(), @core.LOGICAL_HEIGHT)
}

///|
test "the marker row renders in the logical frame" {
  let app = @app.MarkerApp::new()
  let frame = app.frame()
  assert_eq(frame.width(), 120)
  assert_eq(frame.height(), 160)
}
