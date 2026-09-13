// Whitebox tests for the built-in bitmap font. These run inside the package
// and reuse the helpers from canvas_wbtest.mbt (`red`, `wb_px`, `wb_count`)
// to read the private pixel buffer directly and pin exact glyph placement,
// case folding, and clipping.

///|
test "text draws the E glyph with its first pixel exactly at the anchor" {
  let canvas = Canvas::new(width=12, height=12)
  canvas.text(text="E", x=2, y=3, color=red)
  // E pattern: #### / #... / ###. / #... / #### = 13 pixels.
  inspect(wb_count(canvas, red), content="13")
  // The glyph's top-left pixel lands exactly at (x, y).
  inspect(wb_px(canvas, 2, 3), content="63488")
  inspect(wb_px(canvas, 5, 3), content="63488")
  inspect(wb_px(canvas, 2, 4), content="63488")
  inspect(wb_px(canvas, 2, 5), content="63488")
  inspect(wb_px(canvas, 4, 5), content="63488")
  inspect(wb_px(canvas, 2, 6), content="63488")
  inspect(wb_px(canvas, 2, 7), content="63488")
  inspect(wb_px(canvas, 5, 7), content="63488")
  // Empty glyph cells stay untouched.
  inspect(wb_px(canvas, 3, 4), content="0")
  inspect(wb_px(canvas, 5, 4), content="0")
  inspect(wb_px(canvas, 5, 5), content="0")
  inspect(wb_px(canvas, 3, 6), content="0")
}

///|
test "second character's pixels start at x + CHAR_ADVANCE" {
  let canvas = Canvas::new(width=20, height=12)
  canvas.text(text="HI", x=1, y=2, color=red)
  // H = 12 pixels, I = 9 pixels.
  inspect(wb_count(canvas, red), content="21")
  // H row 0 is #..#: columns 1 and 4.
  inspect(wb_px(canvas, 1, 2), content="63488")
  inspect(wb_px(canvas, 4, 2), content="63488")
  // The advance column between the two glyph cells stays empty.
  inspect(wb_px(canvas, 5, 2), content="0")
  inspect(wb_px(canvas, 5, 4), content="0")
  // I starts exactly one CHAR_ADVANCE to the right; row 0 is ###.
  inspect(wb_px(canvas, 6, 2), content="63488")
  inspect(wb_px(canvas, 7, 2), content="63488")
  inspect(wb_px(canvas, 8, 2), content="63488")
  inspect(wb_px(canvas, 9, 2), content="0")
}

///|
test "newline moves to y + LINE_HEIGHT and resets to the anchor x" {
  let canvas = Canvas::new(width=20, height=20)
  canvas.text(text="A\nB", x=2, y=3, color=red)
  // A row 0 is .##.: pixels at (3, 3) and (4, 3), anchor column empty.
  inspect(wb_px(canvas, 2, 3), content="0")
  inspect(wb_px(canvas, 3, 3), content="63488")
  inspect(wb_px(canvas, 4, 3), content="63488")
  // The line-gap row stays empty.
  inspect(wb_px(canvas, 3, 8), content="0")
  // B starts on line 2 at y = 3 + 6, back at the anchor column x = 2.
  inspect(wb_px(canvas, 2, 9), content="63488")
  inspect(wb_px(canvas, 3, 9), content="63488")
  inspect(wb_px(canvas, 4, 9), content="63488")
  inspect(wb_px(canvas, 5, 9), content="0")
}

///|
test "space advances one cell without writing" {
  let canvas = Canvas::new(width=20, height=8)
  canvas.text(text="A B", x=0, y=0, color=red)
  // A = 12 pixels, space = nothing, B = 13 pixels.
  inspect(wb_count(canvas, red), content="25")
  // The space cell (columns 5..8) stays empty.
  inspect(wb_px(canvas, 5, 0), content="0")
  inspect(wb_px(canvas, 8, 0), content="0")
  // B lands after the space, its row 0 (###.) at columns 10..12.
  inspect(wb_px(canvas, 10, 0), content="63488")
  inspect(wb_px(canvas, 11, 0), content="63488")
  inspect(wb_px(canvas, 12, 0), content="63488")
  inspect(wb_px(canvas, 13, 0), content="0")
}

///|
test "unknown character advances one cell without writing, like space" {
  let unknown = Canvas::new(width=20, height=8)
  unknown.text(text="A~B", x=0, y=0, color=red)
  let space = Canvas::new(width=20, height=8)
  space.text(text="A B", x=0, y=0, color=red)
  inspect(wb_count(unknown, red), content="25")
  // '~' behaves exactly like space: identical pixel buffers.
  let mut identical = true
  for i in 0..<unknown.pixels.length() {
    if unknown.pixels[i] != space.pixels[i] {
      identical = false
    }
  }
  inspect(identical, content="true")
}

///|
test "lowercase produces the same pixels as uppercase" {
  let lower = Canvas::new(width=40, height=12)
  lower.text(text="hello 09-:%.!", x=0, y=0, color=red)
  let upper = Canvas::new(width=40, height=12)
  upper.text(text="HELLO 09-:%.!", x=0, y=0, color=red)
  let mut identical = true
  for i in 0..<lower.pixels.length() {
    if lower.pixels[i] != upper.pixels[i] {
      identical = false
    }
  }
  inspect(identical, content="true")
  inspect(wb_count(lower, red) > 0, content="true")
}

///|
test "clipping past the left edge keeps the visible columns" {
  let canvas = Canvas::new(width=8, height=12)
  canvas.text(text="E", x=-2, y=2, color=red)
  // E columns land at -2..1; only columns 0..1 are on canvas.
  inspect(wb_count(canvas, red), content="5")
  // Row 0 (####) keeps columns 0..1; row 2 (###.) keeps column 0.
  inspect(wb_px(canvas, 0, 2), content="63488")
  inspect(wb_px(canvas, 1, 2), content="63488")
  // Row 2 (###.) keeps only its column 2 (canvas column 0).
  inspect(wb_px(canvas, 0, 4), content="63488")
  inspect(wb_px(canvas, 1, 4), content="0")
  inspect(wb_px(canvas, 0, 6), content="63488")
  inspect(wb_px(canvas, 1, 6), content="63488")
  // Row 1's only pixel is the offscreen stem column.
  inspect(wb_px(canvas, 0, 3), content="0")
  inspect(wb_px(canvas, 2, 2), content="0")
}

///|
test "clipping past the right edge is exact at the glyph column boundary" {
  let canvas = Canvas::new(width=6, height=12)
  canvas.text(text="E", x=4, y=1, color=red)
  // E columns land at 4..7; width 6 keeps columns 4..5, so the count is
  // 2 + 1 + 2 + 1 + 2 = 8 and column 5 is the last written one.
  inspect(wb_count(canvas, red), content="8")
  inspect(wb_px(canvas, 4, 1), content="63488")
  inspect(wb_px(canvas, 5, 1), content="63488")
  inspect(wb_px(canvas, 4, 2), content="63488")
  inspect(wb_px(canvas, 4, 3), content="63488")
  inspect(wb_px(canvas, 5, 3), content="63488")
  inspect(wb_px(canvas, 4, 5), content="63488")
  inspect(wb_px(canvas, 5, 5), content="63488")
}

///|
test "clipping past the top edge keeps the visible rows" {
  let canvas = Canvas::new(width=8, height=12)
  canvas.text(text="E", x=1, y=-2, color=red)
  // E rows land at -2..2; glyph rows 2..4 survive: 3 + 1 + 4 = 8 pixels.
  inspect(wb_count(canvas, red), content="8")
  // Row 2 (###.) at canvas row 0.
  inspect(wb_px(canvas, 1, 0), content="63488")
  inspect(wb_px(canvas, 3, 0), content="63488")
  // Row 3 (#...) at canvas row 1.
  inspect(wb_px(canvas, 1, 1), content="63488")
  // Row 4 (####) at canvas row 2.
  inspect(wb_px(canvas, 1, 2), content="63488")
  inspect(wb_px(canvas, 4, 2), content="63488")
}

///|
test "clipping past the bottom edge is exact at the glyph row boundary" {
  let canvas = Canvas::new(width=8, height=6)
  canvas.text(text="E", x=1, y=3, color=red)
  // E rows land at 3..7; height 6 keeps rows 3..5 (glyph rows 0..2):
  // 4 + 1 + 3 = 8 pixels and row 5 is the last written one.
  inspect(wb_count(canvas, red), content="8")
  inspect(wb_px(canvas, 1, 3), content="63488")
  inspect(wb_px(canvas, 4, 3), content="63488")
  inspect(wb_px(canvas, 1, 4), content="63488")
  // Row 1 (#...) has its only pixel at column 0 (canvas column 1).
  inspect(wb_px(canvas, 3, 4), content="0")
  inspect(wb_px(canvas, 1, 5), content="63488")
  inspect(wb_px(canvas, 3, 5), content="63488")
  // Row 2 (###.) leaves column 3 empty.
  inspect(wb_px(canvas, 4, 5), content="0")
}

///|
test "fully offscreen text writes nothing" {
  let canvas = Canvas::new(width=8, height=8)
  canvas.text(text="HELLO", x=-40, y=2, color=red) // entirely left
  canvas.text(text="HELLO", x=8, y=2, color=red) // entirely right
  canvas.text(text="A", x=2, y=-10, color=red) // entirely above
  canvas.text(text="A", x=2, y=8, color=red) // entirely below
  canvas.text(text="HI", x=-100, y=-100, color=red)
  canvas.text(text="HI", x=1000, y=1000, color=red)
  canvas.text(text="HI\nYO", x=-1000000, y=1000000, color=red)
  inspect(wb_count(canvas, red), content="0")
}
