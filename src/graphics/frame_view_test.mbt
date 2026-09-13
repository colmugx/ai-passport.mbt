// FrameView is only reachable through Canvas::frame_view — these blackbox
// tests exercise the backend-facing read path from outside the package.

///|
test "frame view exposes logical dimensions" {
  let canvas = Canvas::new(width=3, height=5)
  let frame = canvas.frame_view()
  inspect(frame.width(), content="3")
  inspect(frame.height(), content="5")
}

///|
test "logical frame view is 120x160" {
  let frame = Canvas::logical().frame_view()
  inspect(frame.width(), content="120")
  inspect(frame.height(), content="160")
}

///|
test "copied rows match Color::to_rgb565 for a drawn scene" {
  let canvas = Canvas::new(width=4, height=3)
  let red = @core.Color::rgb(r=255, g=0, b=0)
  let white = @core.Color::rgb(r=255, g=255, b=255)
  canvas.clear(color=red)
  canvas.pixel(x=2, y=1, color=white)
  let frame = canvas.frame_view()
  let row : FixedArray[Int] = FixedArray::make(frame.width(), 0)

  // Row 0 is entirely red; the RGB565 values equal Color::to_rgb565().
  inspect(frame.copy_rgb565_row(y=0, out=row), content="4")
  assert_eq(row[0], red.to_rgb565())
  assert_eq(row[1], red.to_rgb565())
  assert_eq(row[2], red.to_rgb565())
  assert_eq(row[3], red.to_rgb565())

  // Row 1 carries the single white pixel at (2, 1).
  inspect(frame.copy_rgb565_row(y=1, out=row), content="4")
  assert_eq(row[2], white.to_rgb565())
  assert_eq(row[0], red.to_rgb565())
  assert_eq(row[3], red.to_rgb565())

  // Row 2 is red again.
  inspect(frame.copy_rgb565_row(y=2, out=row), content="4")
  assert_eq(row[1], red.to_rgb565())
}

///|
test "copy_rgb565_row rejects out-of-range rows with zero copies" {
  let canvas = Canvas::new(width=2, height=2)
  let frame = canvas.frame_view()
  let row : FixedArray[Int] = FixedArray::make(2, 99)
  inspect(frame.copy_rgb565_row(y=-1, out=row), content="0")
  inspect(frame.copy_rgb565_row(y=2, out=row), content="0")
  // No cell was written on a rejected row.
  inspect(row[0], content="99")
  inspect(row[1], content="99")
}

///|
test "undersized output copies the fitting prefix" {
  let canvas = Canvas::new(width=4, height=1)
  let green = @core.Color::rgb(r=0, g=255, b=0)
  canvas.clear(color=green)
  let frame = canvas.frame_view()
  let row : FixedArray[Int] = FixedArray::make(2, 99)
  inspect(frame.copy_rgb565_row(y=0, out=row), content="2")
  assert_eq(row[0], green.to_rgb565())
  assert_eq(row[1], green.to_rgb565())
}

///|
test "oversized output leaves surplus cells untouched" {
  let canvas = Canvas::new(width=2, height=1)
  let blue = @core.Color::rgb(r=0, g=0, b=255)
  canvas.clear(color=blue)
  let frame = canvas.frame_view()
  let row : FixedArray[Int] = FixedArray::make(5, 99)
  inspect(frame.copy_rgb565_row(y=0, out=row), content="2")
  assert_eq(row[0], blue.to_rgb565())
  assert_eq(row[1], blue.to_rgb565())
  // Surplus cells keep their original content.
  inspect(row[2], content="99")
  inspect(row[3], content="99")
  inspect(row[4], content="99")
}

///|
test "zero-length output copies nothing" {
  let canvas = Canvas::new(width=2, height=1)
  let frame = canvas.frame_view()
  let row : FixedArray[Int] = FixedArray::make(0, 0)
  inspect(frame.copy_rgb565_row(y=0, out=row), content="0")
}

///|
test "view shares canvas storage and reflects later mutation" {
  // Documented lifetime contract made observable: a FrameView is valid until
  // the source canvas is mutated again; a sink that reads late sees the new
  // pixels, so backends must consume synchronously or copy.
  let canvas = Canvas::new(width=2, height=1)
  let frame = canvas.frame_view()
  let before : FixedArray[Int] = FixedArray::make(2, 0)
  inspect(frame.copy_rgb565_row(y=0, out=before), content="2")
  inspect(before[0], content="0") // fresh canvas is black

  let yellow = @core.Color::rgb(r=255, g=255, b=0)
  canvas.pixel(x=0, y=0, color=yellow)
  let after : FixedArray[Int] = FixedArray::make(2, 0)
  inspect(frame.copy_rgb565_row(y=0, out=after), content="2")
  assert_eq(after[0], yellow.to_rgb565())
}

///|
test "two runs of the same scene produce identical frames" {
  // Display-path determinism: the same drawing operations on two fresh
  // canvases must yield byte-identical RGB565 frames, so a preview and a
  // device run of one app agree pixel for pixel.
  fn draw_scene() -> Canvas {
    let canvas = Canvas::logical()
    canvas.clear(color=@core.Color::rgb(r=20, g=24, b=40))
    canvas.fill_rect(
      x=0,
      y=120,
      w=120,
      h=40,
      color=@core.Color::rgb(r=30, g=90, b=40),
    )
    canvas.line(
      x0=0,
      y0=118,
      x1=119,
      y1=118,
      color=@core.Color::rgb(r=90, g=160, b=90),
    )
    canvas.rect(
      x=4,
      y=4,
      w=30,
      h=10,
      color=@core.Color::rgb(r=255, g=255, b=255),
    )
    canvas.text(
      text="FOREST WALK",
      x=6,
      y=6,
      color=@core.Color::rgb(r=250, g=210, b=60),
    )
    canvas
  }

  let a = draw_scene().frame_view()
  let b = draw_scene().frame_view()
  let row_a : FixedArray[Int] = FixedArray::make(a.width(), 0)
  let row_b : FixedArray[Int] = FixedArray::make(b.width(), 0)
  let mut identical = true
  for y in 0..<a.height() {
    inspect(a.copy_rgb565_row(y~, out=row_a), content="120")
    inspect(b.copy_rgb565_row(y~, out=row_b), content="120")
    for i in 0..<row_a.length() {
      if row_a[i] != row_b[i] {
        identical = false
      }
    }
  }
  inspect(identical, content="true")
}
