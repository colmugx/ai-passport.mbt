///|
test "battery and volume bar widths scale onto the logical width" {
  assert_eq(@app.battery_bar_width(Some(0)), 0)
  assert_eq(@app.battery_bar_width(Some(50)), 60)
  assert_eq(@app.battery_bar_width(Some(100)), 120)
  assert_eq(@app.battery_bar_width(None), 0)
  assert_eq(@app.volume_bar_width(0), 0)
  assert_eq(@app.volume_bar_width(40), 48)
  assert_eq(@app.volume_bar_width(100), 120)
}

///|
fn press(app : &@application.Application, button : @input.Button) -> Unit {
  app.button(button, true)
  app.button(button, false)
}

///|
test "buttons step the volume, clamp at the ends, and toggle mute" {
  let app = @app.passport_main()
  debug_inspect(app.audio_output(), content="Some({ volume: 80, muted: false })")
  press(app, @input.Up)
  press(app, @input.Up)
  debug_inspect(app.audio_output(), content="Some({ volume: 100, muted: false })")
  press(app, @input.Up)
  debug_inspect(app.audio_output(), content="Some({ volume: 100, muted: false })")
  press(app, @input.Down)
  press(app, @input.Down)
  press(app, @input.Down)
  debug_inspect(app.audio_output(), content="Some({ volume: 70, muted: false })")
  press(app, @input.Ok)
  debug_inspect(app.audio_output(), content="Some({ volume: 70, muted: true })")
  for _ in 0..<8 {
    press(app, @input.Down)
  }
  debug_inspect(app.audio_output(), content="Some({ volume: 0, muted: true })")
  press(app, @input.Down)
  debug_inspect(app.audio_output(), content="Some({ volume: 0, muted: true })")
}

///|
test "button edges through the contract latch on press only" {
  let app = @app.passport_main()
  app.button(@input.Up, true)
  app.button(@input.Up, false)
  app.button(@input.Up, false)
  debug_inspect(app.audio_output(), content="Some({ volume: 90, muted: false })")
}

///|
test "host facts drive the panel markers" {
  let app = @app.passport_main()
  app.update(
    {
      now_us: 0L,
      playback_position_us: None,
      presentation_lead_us: 0L,
    },
  )
  app.update(
    {
      now_us: 250_000L,
      playback_position_us: None,
      presentation_lead_us: 0L,
    },
  )
  // No playback: the time marker moves, the playback marker stays dark.
  ignore(app.render(Some(82)))
  // Playback starts: the marker position derives from the position fact.
  app.update(
    {
      now_us: 500_000L,
      playback_position_us: Some(100_000L),
      presentation_lead_us: 100_000L,
    },
  )
  let frame = app.render(Some(82))
  assert_eq(frame.width(), @core.LOGICAL_WIDTH)
  assert_eq(frame.height(), @core.LOGICAL_HEIGHT)
}
