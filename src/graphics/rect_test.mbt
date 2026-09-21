// Blackbox tests: public API behavior only, no internal access.

///|
test "rect never panics on wild arguments" {
  let canvas = @graphics.Canvas::new(width=8, height=8)
  let red = @core.Color::rgb(r=255, g=0, b=0)
  canvas.rect(x=-1, y=-1, w=0, h=0, color=red)
  canvas.rect(x=0, y=0, w=-5, h=3, color=red)
  canvas.rect(x=-1000000, y=-1000000, w=2000000, h=2000000, color=red)
  canvas.rect(x=-3, y=-3, w=10, h=10, color=red)
  canvas.rect(x=6, y=6, w=100, h=100, color=red)
  canvas.rect(x=2147483647, y=2147483647, w=2147483647, h=2147483647, color=red)
  canvas.rect(
    x=-2147483648,
    y=-2147483648,
    w=-2147483648,
    h=-2147483648,
    color=red,
  )
}

///|
test "rect draws on the default logical canvas" {
  let canvas = @graphics.Canvas::logical()
  let white = @core.Color::rgb(r=255, g=255, b=255)
  // Full-canvas border plus an interior box.
  canvas.rect(x=0, y=0, w=120, h=160, color=white)
  canvas.rect(x=10, y=10, w=20, h=20, color=white)
}
