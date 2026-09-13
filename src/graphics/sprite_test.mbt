// Blackbox tests: public API behavior only, no internal access.

///|
test "SpriteSheet::from_colors exposes dims and frame count" {
  let sheet = @graphics.SpriteSheet::from_colors(
    frame_width=2,
    frame_height=2,
    pixels=[
      Some(@core.Color::rgb(r=255, g=0, b=0)),
      None,
      None,
      Some(@core.Color::rgb(r=0, g=0, b=255)),
      Some(@core.Color::rgb(r=0, g=255, b=0)),
      Some(@core.Color::rgb(r=0, g=255, b=0)),
      Some(@core.Color::rgb(r=0, g=255, b=0)),
      Some(@core.Color::rgb(r=0, g=255, b=0)),
      None,
      None,
      None,
      None,
    ],
  )
  inspect(sheet.frame_width(), content="2")
  inspect(sheet.frame_height(), content="2")
  inspect(sheet.frame_count(), content="3")
}

///|
test "wild sprite arguments never panic" {
  let sheet = @graphics.SpriteSheet::from_colors(
    frame_width=1,
    frame_height=1,
    pixels=[Some(@core.Color::rgb(r=255, g=255, b=255)), None],
  )
  let canvas = @graphics.Canvas::new(width=4, height=4)
  // Out-of-range frames: negative and far past the end.
  canvas.sprite(sheet~, frame=-2147483648, x=0, y=0)
  canvas.sprite(sheet~, frame=2147483647, x=0, y=0)
  // Extreme destinations on every axis, including exact edge touches.
  canvas.sprite(sheet~, frame=0, x=4, y=0)
  canvas.sprite(sheet~, frame=0, x=0, y=4)
  canvas.sprite(sheet~, frame=0, x=-2147483648, y=-2147483648)
  canvas.sprite(sheet~, frame=0, x=2147483647, y=2147483647)
  // Valid draw with a transparent frame pixel must not panic either.
  canvas.sprite(sheet~, frame=1, x=1, y=1)
}
