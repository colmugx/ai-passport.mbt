// Whitebox tests for Canvas::rect: these compile inside package scope and read
// the private `pixels` buffer to pin the outline contract. Reuses the shared
// helpers (wb_px, wb_count, colors) from canvas_wbtest.mbt.

///|
test "rect fully inside draws only the outline" {
  let canvas = Canvas::new(width=8, height=8)
  canvas.rect(x=2, y=2, w=4, h=3, color=red)
  // Perimeter of a 4x3 outline: 2*4 + 2*3 - 4 = 10 pixels.
  inspect(wb_count(canvas, red), content="10")
  // Corners.
  inspect(wb_px(canvas, 2, 2), content="63488")
  inspect(wb_px(canvas, 5, 2), content="63488")
  inspect(wb_px(canvas, 2, 4), content="63488")
  inspect(wb_px(canvas, 5, 4), content="63488")
  // Edge midpoints.
  inspect(wb_px(canvas, 3, 2), content="63488")
  inspect(wb_px(canvas, 2, 3), content="63488")
  inspect(wb_px(canvas, 5, 3), content="63488")
  inspect(wb_px(canvas, 3, 4), content="63488")
  // Interior is untouched.
  inspect(wb_px(canvas, 3, 3), content="0")
  inspect(wb_px(canvas, 4, 3), content="0")
  // Neighbors outside are untouched.
  inspect(wb_px(canvas, 1, 2), content="0")
  inspect(wb_px(canvas, 6, 2), content="0")
  inspect(wb_px(canvas, 2, 1), content="0")
  inspect(wb_px(canvas, 2, 5), content="0")
}

///|
test "rect clips on the left edge" {
  let canvas = Canvas::new(width=8, height=8)
  canvas.rect(x=-2, y=2, w=5, h=3, color=green)
  // Visible part: columns 0..2, rows 2..4; the left edge itself is offscreen.
  inspect(wb_count(canvas, green), content="7")
  inspect(wb_px(canvas, 0, 2), content="2016")
  inspect(wb_px(canvas, 2, 2), content="2016")
  inspect(wb_px(canvas, 0, 4), content="2016")
  inspect(wb_px(canvas, 2, 3), content="2016")
  inspect(wb_px(canvas, 0, 3), content="0")
  inspect(wb_px(canvas, 1, 3), content="0")
  inspect(wb_px(canvas, 3, 2), content="0")
}

///|
test "rect clips on the right edge" {
  let canvas = Canvas::new(width=8, height=8)
  canvas.rect(x=5, y=2, w=5, h=3, color=red)
  // Visible part: columns 5..7, rows 2..4; the right edge itself is offscreen.
  inspect(wb_count(canvas, red), content="7")
  inspect(wb_px(canvas, 5, 2), content="63488")
  inspect(wb_px(canvas, 7, 2), content="63488")
  inspect(wb_px(canvas, 5, 4), content="63488")
  inspect(wb_px(canvas, 7, 4), content="63488")
  inspect(wb_px(canvas, 5, 3), content="63488")
  inspect(wb_px(canvas, 6, 3), content="0")
  inspect(wb_px(canvas, 4, 2), content="0")
}

///|
test "rect clips on the top edge" {
  let canvas = Canvas::new(width=8, height=8)
  canvas.rect(x=2, y=-2, w=3, h=5, color=blue)
  // Visible part: columns 2..4, rows 0..2; the top edge itself is offscreen.
  inspect(wb_count(canvas, blue), content="7")
  inspect(wb_px(canvas, 2, 0), content="31")
  inspect(wb_px(canvas, 4, 0), content="31")
  inspect(wb_px(canvas, 2, 2), content="31")
  inspect(wb_px(canvas, 3, 2), content="31")
  inspect(wb_px(canvas, 4, 2), content="31")
  inspect(wb_px(canvas, 2, 1), content="31")
  inspect(wb_px(canvas, 4, 1), content="31")
  inspect(wb_px(canvas, 3, 1), content="0")
  inspect(wb_px(canvas, 2, 3), content="0")
}

///|
test "rect clips on the bottom edge" {
  let canvas = Canvas::new(width=8, height=8)
  canvas.rect(x=2, y=5, w=3, h=5, color=white)
  // Visible part: columns 2..4, rows 5..7; the bottom edge itself is offscreen.
  inspect(wb_count(canvas, white), content="7")
  inspect(wb_px(canvas, 2, 5), content="65535")
  inspect(wb_px(canvas, 3, 5), content="65535")
  inspect(wb_px(canvas, 4, 5), content="65535")
  inspect(wb_px(canvas, 2, 6), content="65535")
  inspect(wb_px(canvas, 2, 7), content="65535")
  inspect(wb_px(canvas, 4, 6), content="65535")
  inspect(wb_px(canvas, 4, 7), content="65535")
  inspect(wb_px(canvas, 3, 6), content="0")
  inspect(wb_px(canvas, 3, 7), content="0")
}

///|
test "rect fully offscreen writes nothing" {
  let canvas = Canvas::new(width=8, height=8)
  canvas.rect(x=-5, y=2, w=3, h=2, color=red) // entirely left
  canvas.rect(x=9, y=2, w=3, h=2, color=red) // entirely right, x > width
  canvas.rect(x=2, y=-5, w=3, h=2, color=red) // entirely above
  canvas.rect(x=2, y=9, w=3, h=2, color=red) // entirely below, y > height
  canvas.rect(x=-100, y=-100, w=10, h=10, color=red)
  canvas.rect(x=1000, y=1000, w=10, h=10, color=red)
  inspect(wb_count(canvas, red), content="0")
}

///|
test "rect with zero or negative size writes nothing" {
  let canvas = Canvas::new(width=8, height=8)
  canvas.rect(x=0, y=0, w=0, h=0, color=red)
  canvas.rect(x=1, y=1, w=0, h=2, color=red)
  canvas.rect(x=1, y=1, w=2, h=0, color=red)
  canvas.rect(x=1, y=1, w=-2, h=2, color=red)
  canvas.rect(x=1, y=1, w=2, h=-2, color=red)
  canvas.rect(x=1, y=1, w=-1, h=-1, color=red)
  inspect(wb_count(canvas, red), content="0")
}

///|
test "rect with w == 1 collapses to a vertical line" {
  let canvas = Canvas::new(width=8, height=8)
  canvas.rect(x=3, y=1, w=1, h=5, color=red)
  inspect(wb_count(canvas, red), content="5")
  inspect(wb_px(canvas, 3, 1), content="63488")
  inspect(wb_px(canvas, 3, 3), content="63488")
  inspect(wb_px(canvas, 3, 5), content="63488")
  inspect(wb_px(canvas, 2, 3), content="0")
  inspect(wb_px(canvas, 4, 3), content="0")
  inspect(wb_px(canvas, 3, 0), content="0")
  inspect(wb_px(canvas, 3, 6), content="0")
}

///|
test "rect with h == 1 collapses to a horizontal line" {
  let canvas = Canvas::new(width=8, height=8)
  canvas.rect(x=1, y=3, w=5, h=1, color=green)
  inspect(wb_count(canvas, green), content="5")
  inspect(wb_px(canvas, 1, 3), content="2016")
  inspect(wb_px(canvas, 3, 3), content="2016")
  inspect(wb_px(canvas, 5, 3), content="2016")
  inspect(wb_px(canvas, 1, 2), content="0")
  inspect(wb_px(canvas, 1, 4), content="0")
  inspect(wb_px(canvas, 0, 3), content="0")
  inspect(wb_px(canvas, 6, 3), content="0")
}

///|
test "rect with 1x1 draws a single pixel" {
  let canvas = Canvas::new(width=8, height=8)
  canvas.rect(x=4, y=4, w=1, h=1, color=white)
  inspect(wb_count(canvas, white), content="1")
  inspect(wb_px(canvas, 4, 4), content="65535")
  inspect(wb_px(canvas, 3, 4), content="0")
  inspect(wb_px(canvas, 5, 4), content="0")
  inspect(wb_px(canvas, 4, 3), content="0")
  inspect(wb_px(canvas, 4, 5), content="0")
}

///|
test "rect writes the last column and row but nothing beyond" {
  let full = Canvas::new(width=8, height=8)
  full.rect(x=0, y=0, w=8, h=8, color=red)
  // Border of the whole canvas: 2*8 + 2*8 - 4 = 28 pixels; storage stays
  // exactly width * height cells, so nothing was written past the edges.
  inspect(full.pixels.length(), content="64")
  inspect(wb_count(full, red), content="28")
  inspect(wb_px(full, 7, 0), content="63488")
  inspect(wb_px(full, 0, 7), content="63488")
  inspect(wb_px(full, 7, 7), content="63488")
  inspect(wb_px(full, 3, 3), content="0")

  let inner = Canvas::new(width=8, height=8)
  inner.rect(x=2, y=2, w=6, h=6, color=blue)
  // Right edge sits exactly on column 7, bottom edge on row 7:
  // 2*6 + 2*6 - 4 = 20 pixels.
  inspect(wb_count(inner, blue), content="20")
  inspect(wb_px(inner, 7, 2), content="31")
  inspect(wb_px(inner, 2, 7), content="31")
  inspect(wb_px(inner, 7, 7), content="31")
  inspect(wb_px(inner, 3, 3), content="0")
}

///|
test "second rect draw wins" {
  let canvas = Canvas::new(width=8, height=8)
  canvas.rect(x=1, y=1, w=4, h=3, color=red)
  canvas.rect(x=1, y=1, w=4, h=3, color=blue)
  inspect(wb_count(canvas, blue), content="10")
  inspect(wb_count(canvas, red), content="0")
}
