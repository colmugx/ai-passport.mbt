// Blackbox tests: public API behavior only, no internal access.

///|
test "line never panics on wild arguments" {
  let canvas = @graphics.Canvas::new(width=8, height=8)
  let red = @core.Color::rgb(r=255, g=0, b=0)
  // Fully offscreen segments.
  canvas.line(x0=-1, y0=-1, x1=-100, y1=-100, color=red)
  canvas.line(x0=8, y0=0, x1=100, y1=0, color=red)
  canvas.line(x0=0, y0=8, x1=0, y1=100, color=red)
  // Long segments crossing the canvas from far outside.
  canvas.line(x0=-1000000, y0=-1000000, x1=1000000, y1=1000000, color=red)
  canvas.line(x0=-100, y0=-50, x1=200, y1=150, color=red)
  // Extreme coordinates with finite spans.
  canvas.line(
    x0=2147483647,
    y0=2147483647,
    x1=2147483647,
    y1=2147483647,
    color=red,
  )
  canvas.line(
    x0=-2147483648,
    y0=-2147483648,
    x1=-2147483000,
    y1=-2147483000,
    color=red,
  )
  canvas.line(x0=2147483000, y0=5, x1=2147483647, y1=5, color=red)
}

///|
test "line draws on the default logical canvas" {
  let canvas = @graphics.Canvas::logical()
  let white = @core.Color::rgb(r=255, g=255, b=255)
  canvas.line(x0=0, y0=0, x1=119, y1=159, color=white)
  // The reversed segment must behave identically and never panic either.
  canvas.line(x0=119, y0=159, x1=0, y1=0, color=white)
}
