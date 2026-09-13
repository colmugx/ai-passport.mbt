// Whitebox tests for Canvas::line: these compile inside package scope and read
// the private `pixels` buffer to pin exact pixel sets. Reuses the shared
// helpers (wb_px, wb_count, colors) from canvas_wbtest.mbt.

///|
/// Test helper: true when both canvases hold identical internal storage.
fn wb_line_eq(a : Canvas, b : Canvas) -> Bool {
  if a.width != b.width || a.height != b.height {
    return false
  }
  let pa = a.pixels
  let pb = b.pixels
  for i in 0..<pa.length() {
    if pa[i] != pb[i] {
      return false
    }
  }
  true
}

///|
test "line draws a horizontal run" {
  let canvas = Canvas::new(width=8, height=8)
  canvas.line(x0=1, y0=2, x1=5, y1=2, color=red)
  inspect(wb_count(canvas, red), content="5")
  inspect(wb_px(canvas, 1, 2), content="63488")
  inspect(wb_px(canvas, 3, 2), content="63488")
  inspect(wb_px(canvas, 5, 2), content="63488")
  inspect(wb_px(canvas, 1, 1), content="0")
  inspect(wb_px(canvas, 1, 3), content="0")
  inspect(wb_px(canvas, 0, 2), content="0")
  inspect(wb_px(canvas, 6, 2), content="0")
}

///|
test "line draws a vertical run" {
  let canvas = Canvas::new(width=8, height=8)
  canvas.line(x0=3, y0=1, x1=3, y1=6, color=green)
  inspect(wb_count(canvas, green), content="6")
  inspect(wb_px(canvas, 3, 1), content="2016")
  inspect(wb_px(canvas, 3, 6), content="2016")
  inspect(wb_px(canvas, 2, 3), content="0")
  inspect(wb_px(canvas, 4, 3), content="0")
}

///|
test "line draws a 45 degree diagonal" {
  let canvas = Canvas::new(width=8, height=8)
  canvas.line(x0=0, y0=0, x1=4, y1=4, color=blue)
  inspect(wb_count(canvas, blue), content="5")
  inspect(wb_px(canvas, 0, 0), content="31")
  inspect(wb_px(canvas, 2, 2), content="31")
  inspect(wb_px(canvas, 4, 4), content="31")
  // Neighbors off the diagonal stay untouched.
  inspect(wb_px(canvas, 1, 0), content="0")
  inspect(wb_px(canvas, 0, 1), content="0")
  inspect(wb_px(canvas, 2, 1), content="0")
  inspect(wb_px(canvas, 1, 2), content="0")
}

///|
test "line draws a steep non-45 diagonal" {
  let canvas = Canvas::new(width=8, height=8)
  canvas.line(x0=1, y0=1, x1=2, y1=5, color=blue)
  inspect(wb_count(canvas, blue), content="5")
  inspect(wb_px(canvas, 1, 1), content="31")
  inspect(wb_px(canvas, 1, 2), content="31")
  inspect(wb_px(canvas, 2, 3), content="31")
  inspect(wb_px(canvas, 2, 4), content="31")
  inspect(wb_px(canvas, 2, 5), content="31")
  inspect(wb_px(canvas, 2, 1), content="0")
  inspect(wb_px(canvas, 2, 2), content="0")
  inspect(wb_px(canvas, 1, 3), content="0")
  inspect(wb_px(canvas, 1, 5), content="0")
}

///|
test "line with identical endpoints draws a single point" {
  let canvas = Canvas::new(width=8, height=8)
  canvas.line(x0=4, y0=4, x1=4, y1=4, color=white)
  inspect(wb_count(canvas, white), content="1")
  inspect(wb_px(canvas, 4, 4), content="65535")
}

///|
test "line tie-breaking is identical for reversed endpoints" {
  let forward = Canvas::new(width=8, height=8)
  let backward = Canvas::new(width=8, height=8)
  forward.line(x0=0, y0=0, x1=2, y1=1, color=red)
  backward.line(x0=2, y0=1, x1=0, y1=0, color=red)
  assert_true(wb_line_eq(forward, backward))
  inspect(wb_count(forward, red), content="3")
  inspect(wb_px(forward, 0, 0), content="63488")
  inspect(wb_px(forward, 1, 1), content="63488")
  inspect(wb_px(forward, 2, 1), content="63488")
  inspect(wb_px(forward, 1, 0), content="0")
}

///|
test "line covers max(dx, dy) + 1 pixels and is endpoint-order symmetric" {
  let points = [
    (0, 0),
    (16, 0),
    (0, 16),
    (16, 16),
    (8, 8),
    (5, 2),
    (2, 5),
    (13, 7),
    (7, 13),
    (1, 15),
    (15, 1),
    (0, 8),
    (8, 0),
    (16, 8),
    (8, 16),
    (3, 3),
  ]
  for (sx, sy) in points {
    for (ex, ey) in points {
      let forward = Canvas::new(width=17, height=17)
      let backward = Canvas::new(width=17, height=17)
      forward.line(x0=sx, y0=sy, x1=ex, y1=ey, color=red)
      backward.line(x0=ex, y0=ey, x1=sx, y1=sy, color=red)
      assert_true(wb_line_eq(forward, backward))
      let expected = (ex - sx).abs().max((ey - sy).abs()) + 1
      assert_eq(wb_count(forward, red), expected)
    }
  }
}

///|
test "line clips when one endpoint is offscreen" {
  let horizontal = Canvas::new(width=8, height=8)
  horizontal.line(x0=-2, y0=1, x1=4, y1=1, color=red)
  inspect(wb_count(horizontal, red), content="5")
  inspect(wb_px(horizontal, 0, 1), content="63488")
  inspect(wb_px(horizontal, 4, 1), content="63488")
  inspect(wb_px(horizontal, 5, 1), content="0")

  let vertical = Canvas::new(width=8, height=8)
  vertical.line(x0=6, y0=-3, x1=6, y1=3, color=green)
  inspect(wb_count(vertical, green), content="4")
  inspect(wb_px(vertical, 6, 0), content="2016")
  inspect(wb_px(vertical, 6, 3), content="2016")
  inspect(wb_px(vertical, 6, 4), content="0")
}

///|
test "line clips when both endpoints are offscreen but the segment crosses" {
  let diagonal = Canvas::new(width=8, height=8)
  diagonal.line(x0=-2, y0=-2, x1=10, y1=10, color=red)
  // Visible middle: the on-canvas diagonal (0,0)..(7,7).
  inspect(wb_count(diagonal, red), content="8")
  inspect(wb_px(diagonal, 0, 0), content="63488")
  inspect(wb_px(diagonal, 7, 7), content="63488")
  inspect(wb_px(diagonal, 0, 1), content="0")

  let horizontal = Canvas::new(width=8, height=8)
  horizontal.line(x0=-5, y0=3, x1=12, y1=3, color=green)
  inspect(wb_count(horizontal, green), content="8")
  inspect(wb_px(horizontal, 0, 3), content="2016")
  inspect(wb_px(horizontal, 7, 3), content="2016")

  let vertical = Canvas::new(width=8, height=8)
  vertical.line(x0=3, y0=-4, x1=3, y1=11, color=blue)
  inspect(wb_count(vertical, blue), content="8")
  inspect(wb_px(vertical, 3, 0), content="31")
  inspect(wb_px(vertical, 3, 7), content="31")
}

///|
test "line writes the last column and row but nothing beyond" {
  let diagonal = Canvas::new(width=8, height=8)
  diagonal.line(x0=0, y0=0, x1=7, y1=7, color=red)
  // Storage is exactly width * height cells; the bottom-right corner
  // (width-1, height-1) is the last one and gets written, nothing past it.
  inspect(diagonal.pixels.length(), content="64")
  inspect(wb_count(diagonal, red), content="8")
  inspect(wb_px(diagonal, 7, 7), content="63488")

  let bottom = Canvas::new(width=8, height=8)
  bottom.line(x0=0, y0=7, x1=7, y1=7, color=green)
  inspect(wb_count(bottom, green), content="8")
  inspect(wb_px(bottom, 0, 7), content="2016")
  inspect(wb_px(bottom, 7, 7), content="2016")

  let right = Canvas::new(width=8, height=8)
  right.line(x0=7, y0=0, x1=7, y1=7, color=blue)
  inspect(wb_count(right, blue), content="8")
  inspect(wb_px(right, 7, 0), content="31")
  inspect(wb_px(right, 7, 7), content="31")
}
