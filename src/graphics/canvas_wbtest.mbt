// Whitebox tests: these compile inside package scope and may read the
// private `pixels` buffer to pin the internal storage contract.

///|
/// Distinct test colors so mixed writes can never alias.
let red : @core.Color = @core.Color::rgb(r=255, g=0, b=0)

///|
let green : @core.Color = @core.Color::rgb(r=0, g=255, b=0)

///|
let blue : @core.Color = @core.Color::rgb(r=0, g=0, b=255)

///|
let white : @core.Color = @core.Color::rgb(r=255, g=255, b=255)

///|
let black : @core.Color = @core.Color::rgb(r=0, g=0, b=0)

///|
/// Test helper: reads the raw internal storage value at (`x`, `y`).
fn wb_px(canvas : Canvas, x : Int, y : Int) -> Int {
  canvas.pixels[y * canvas.width + x].to_int()
}

///|
/// Test helper: counts internal storage cells holding `color`.
fn wb_count(canvas : Canvas, color : @core.Color) -> Int {
  let value = color.to_rgb565().to_uint16()
  let pixels = canvas.pixels
  let mut hits = 0
  for i in 0..<pixels.length() {
    if pixels[i] == value {
      hits += 1
    }
  }
  hits
}

///|
test "fresh canvas stores width * height cells, all black" {
  let canvas = Canvas::new(width=4, height=5)
  inspect(canvas.pixels.length(), content="20")
  inspect(wb_count(canvas, black), content="20")
}

///|
test "pixel ignores negative, edge, and fully offscreen coordinates" {
  let canvas = Canvas::new(width=4, height=5)
  canvas.pixel(x=-1, y=2, color=red)
  canvas.pixel(x=2, y=-1, color=red)
  canvas.pixel(x=4, y=2, color=red) // x == width, right edge exclusive
  canvas.pixel(x=2, y=5, color=red) // y == height, bottom edge exclusive
  canvas.pixel(x=-100, y=-100, color=red) // fully offscreen
  canvas.pixel(x=1000, y=1000, color=red)
  inspect(wb_count(canvas, red), content="0")
  inspect(wb_count(canvas, black), content="20")
}

///|
test "pixel writes the first and last pixels" {
  let first = Canvas::new(width=4, height=5)
  first.pixel(x=0, y=0, color=red)
  inspect(wb_px(first, 0, 0), content="63488")
  inspect(wb_count(first, red), content="1")

  let last = Canvas::new(width=4, height=5)
  last.pixel(x=3, y=4, color=green)
  inspect(wb_px(last, 3, 4), content="2016")
  inspect(wb_count(last, green), content="1")
}

///|
test "pixel writes exactly one cell per call" {
  let canvas = Canvas::new(width=4, height=5)
  canvas.pixel(x=2, y=1, color=blue)
  inspect(wb_px(canvas, 2, 1), content="31")
  inspect(wb_count(canvas, blue), content="1")
  inspect(wb_count(canvas, black), content="19")
}

///|
test "fill_rect fully inside writes exactly the rectangle" {
  let canvas = Canvas::new(width=8, height=8)
  canvas.fill_rect(x=2, y=3, w=3, h=2, color=green)
  inspect(wb_count(canvas, green), content="6")
  inspect(wb_count(canvas, black), content="58")
  // Corners of the filled region [2, 5) x [3, 5).
  inspect(wb_px(canvas, 2, 3), content="2016")
  inspect(wb_px(canvas, 4, 3), content="2016")
  inspect(wb_px(canvas, 2, 4), content="2016")
  inspect(wb_px(canvas, 4, 4), content="2016")
  // Immediate neighbors stay untouched.
  inspect(wb_px(canvas, 1, 3), content="0")
  inspect(wb_px(canvas, 5, 3), content="0")
  inspect(wb_px(canvas, 2, 2), content="0")
  inspect(wb_px(canvas, 2, 5), content="0")
}

///|
test "fill_rect clips to the visible part past the left edge" {
  let canvas = Canvas::new(width=4, height=5)
  canvas.fill_rect(x=-2, y=1, w=4, h=2, color=red)
  // Visible part: columns 0..1, rows 1..2.
  inspect(wb_count(canvas, red), content="4")
  inspect(wb_px(canvas, 0, 1), content="63488")
  inspect(wb_px(canvas, 1, 2), content="63488")
  inspect(wb_px(canvas, 2, 1), content="0")
  inspect(wb_px(canvas, 0, 0), content="0")
  inspect(wb_px(canvas, 0, 3), content="0")
}

///|
test "fill_rect clips to the visible part past the right edge" {
  let canvas = Canvas::new(width=4, height=5)
  canvas.fill_rect(x=3, y=1, w=4, h=2, color=green)
  // Visible part: column 3, rows 1..2.
  inspect(wb_count(canvas, green), content="2")
  inspect(wb_px(canvas, 3, 1), content="2016")
  inspect(wb_px(canvas, 3, 2), content="2016")
  inspect(wb_px(canvas, 2, 1), content="0")
  inspect(wb_px(canvas, 3, 0), content="0")
  inspect(wb_px(canvas, 3, 3), content="0")
}

///|
test "fill_rect clips to the visible part past the top edge" {
  let canvas = Canvas::new(width=4, height=5)
  canvas.fill_rect(x=1, y=-2, w=2, h=4, color=blue)
  // Visible part: columns 1..2, rows 0..1.
  inspect(wb_count(canvas, blue), content="4")
  inspect(wb_px(canvas, 1, 0), content="31")
  inspect(wb_px(canvas, 2, 1), content="31")
  inspect(wb_px(canvas, 0, 0), content="0")
  inspect(wb_px(canvas, 3, 1), content="0")
  inspect(wb_px(canvas, 1, 2), content="0")
}

///|
test "fill_rect clips to the visible part past the bottom edge" {
  let canvas = Canvas::new(width=4, height=5)
  canvas.fill_rect(x=1, y=4, w=2, h=4, color=white)
  // Visible part: columns 1..2, row 4.
  inspect(wb_count(canvas, white), content="2")
  inspect(wb_px(canvas, 1, 4), content="65535")
  inspect(wb_px(canvas, 2, 4), content="65535")
  inspect(wb_px(canvas, 0, 4), content="0")
  inspect(wb_px(canvas, 3, 4), content="0")
  inspect(wb_px(canvas, 1, 3), content="0")
}

///|
test "fill_rect fully offscreen writes nothing" {
  let canvas = Canvas::new(width=4, height=5)
  canvas.fill_rect(x=-8, y=1, w=4, h=2, color=red) // entirely left
  canvas.fill_rect(x=4, y=1, w=4, h=2, color=red) // entirely right, x == width
  canvas.fill_rect(x=1, y=-8, w=2, h=4, color=red) // entirely above
  canvas.fill_rect(x=1, y=5, w=2, h=4, color=red) // entirely below, y == height
  canvas.fill_rect(x=-100, y=-100, w=10, h=10, color=red)
  canvas.fill_rect(x=1000, y=1000, w=10, h=10, color=red)
  inspect(wb_count(canvas, red), content="0")
  inspect(wb_count(canvas, black), content="20")
}

///|
test "fill_rect covering the whole canvas fills every pixel" {
  let overhang = Canvas::new(width=4, height=5)
  overhang.fill_rect(x=-10, y=-10, w=100, h=100, color=white)
  inspect(wb_count(overhang, white), content="20")

  let exact = Canvas::new(width=4, height=5)
  exact.fill_rect(x=0, y=0, w=4, h=5, color=blue)
  inspect(wb_count(exact, blue), content="20")
}

///|
test "fill_rect with zero or negative size writes nothing" {
  let canvas = Canvas::new(width=4, height=5)
  canvas.fill_rect(x=0, y=0, w=0, h=0, color=red)
  canvas.fill_rect(x=1, y=1, w=0, h=2, color=red)
  canvas.fill_rect(x=1, y=1, w=2, h=0, color=red)
  canvas.fill_rect(x=1, y=1, w=-2, h=2, color=red)
  canvas.fill_rect(x=1, y=1, w=2, h=-2, color=red)
  canvas.fill_rect(x=1, y=1, w=-1, h=-1, color=red)
  inspect(wb_count(canvas, red), content="0")
  inspect(wb_count(canvas, black), content="20")
}

///|
test "clear fills every pixel" {
  let canvas = Canvas::new(width=4, height=5)
  canvas.pixel(x=2, y=2, color=red)
  canvas.clear(color=green)
  inspect(wb_count(canvas, green), content="20")
  inspect(wb_count(canvas, red), content="0")
}

///|
test "second draw wins for pixel, fill_rect, and clear" {
  let canvas = Canvas::new(width=4, height=5)
  canvas.fill_rect(x=1, y=1, w=2, h=2, color=red)
  canvas.fill_rect(x=1, y=1, w=2, h=2, color=blue)
  inspect(wb_count(canvas, blue), content="4")
  inspect(wb_count(canvas, red), content="0")

  canvas.pixel(x=3, y=4, color=red)
  canvas.pixel(x=3, y=4, color=white)
  inspect(wb_px(canvas, 3, 4), content="65535")
  inspect(wb_count(canvas, red), content="0")

  canvas.clear(color=green)
  canvas.clear(color=white)
  inspect(wb_count(canvas, white), content="20")
  inspect(wb_count(canvas, green), content="0")
}
