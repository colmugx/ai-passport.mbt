// Blackbox tests: public API behavior only, no internal access.

///|
test "Canvas::logical matches the 120x160 v0.1 logical display" {
  let canvas = @graphics.Canvas::logical()
  debug_inspect((canvas.width(), canvas.height()), content="(120, 160)")
}

///|
test "panic Canvas::new aborts on zero width" {
  ignore(@graphics.Canvas::new(width=0, height=160))
}

///|
test "panic Canvas::new aborts on negative height" {
  ignore(@graphics.Canvas::new(width=120, height=-1))
}

///|
test "Canvas::new accepts positive dimensions and reports them" {
  let canvas = @graphics.Canvas::new(width=7, height=3)
  inspect(canvas.width(), content="7")
  inspect(canvas.height(), content="3")
}

///|
test "out-of-bounds drawing never panics" {
  let canvas = @graphics.Canvas::new(width=4, height=5)
  let red = @core.Color::rgb(r=255, g=0, b=0)
  canvas.pixel(x=-1, y=-1, color=red)
  canvas.pixel(x=4, y=0, color=red)
  canvas.pixel(x=0, y=5, color=red)
  canvas.pixel(x=-1000000, y=1000000, color=red)
  canvas.fill_rect(x=-1000000, y=-1000000, w=2000000, h=2000000, color=red)
  canvas.fill_rect(
    x=2147483647,
    y=2147483647,
    w=2147483647,
    h=2147483647,
    color=red,
  )
  canvas.fill_rect(x=0, y=0, w=0, h=0, color=red)
  canvas.fill_rect(x=-10, y=-10, w=-10, h=-10, color=red)
}
