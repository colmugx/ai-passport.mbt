// Whitebox tests: these compile inside package scope and read the private
// `pixels` buffers of both Canvas and SpriteSheet to pin the internal
// storage contract (RGB565 values, -1 transparent sentinel, row-major
// frame addressing). Colors and canvas helpers are shared with
// canvas_wbtest.mbt.

///|
/// Test helper: reads the raw internal storage value for pixel (`fx`, `fy`)
/// of frame `frame`.
fn sprite_px(sheet : SpriteSheet, frame : Int, fx : Int, fy : Int) -> Int {
  let base = frame * sheet.frame_width * sheet.frame_height
  sheet.pixels[base + fy * sheet.frame_width + fx]
}

///|
/// Test helper: counts canvas storage cells holding the -1 transparency
/// sentinel. Drawing must never leak the sentinel into the canvas.
fn sprite_sentinel_count(canvas : Canvas) -> Int {
  let mut hits = 0
  for i in 0..<canvas.pixels.length() {
    if canvas.pixels[i] == -1 {
      hits += 1
    }
  }
  hits
}

///|
/// 2x2 sheet with three row-major frames:
/// frame 0 = red, green / blue, white
/// frame 1 = black, black / black, black
/// frame 2 = white, blue / green, red
fn sprite_fixture() -> SpriteSheet {
  SpriteSheet::from_colors(frame_width=2, frame_height=2, pixels=[
    Some(red),
    Some(green),
    Some(blue),
    Some(white),
    Some(black),
    Some(black),
    Some(black),
    Some(black),
    Some(white),
    Some(blue),
    Some(green),
    Some(red),
  ])
}

///|
test "from_colors reports dims, frame count, and row-major frame storage" {
  let sheet = sprite_fixture()
  inspect(sheet.frame_width(), content="2")
  inspect(sheet.frame_height(), content="2")
  inspect(sheet.frame_count(), content="3")
  inspect(sheet.pixels.length(), content="12")
  // Frame blocks follow the pixel array in row-major order:
  // frame 0 first, frame 1 next, frame 2 last.
  inspect(sprite_px(sheet, 0, 0, 0), content="63488") // red
  inspect(sprite_px(sheet, 1, 0, 0), content="0") // black
  inspect(sprite_px(sheet, 2, 0, 0), content="65535") // white
}

///|
test "from_colors stores RGB565 values and -1 for transparent pixels" {
  let sheet = SpriteSheet::from_colors(frame_width=2, frame_height=1, pixels=[
    Some(red),
    None,
    None,
    Some(blue),
  ])
  inspect(sheet.frame_count(), content="2")
  inspect(sprite_px(sheet, 0, 0, 0), content="63488") // red
  inspect(sprite_px(sheet, 0, 1, 0), content="-1") // transparent sentinel
  inspect(sprite_px(sheet, 1, 0, 0), content="-1") // transparent sentinel
  inspect(sprite_px(sheet, 1, 1, 0), content="31") // blue
}

///|
test "panic SpriteSheet::from_colors aborts on zero frame_width" {
  ignore(
    SpriteSheet::from_colors(frame_width=0, frame_height=2, pixels=[
      Some(red),
      Some(red),
      Some(red),
      Some(red),
    ]),
  )
}

///|
test "panic SpriteSheet::from_colors aborts on negative frame_height" {
  ignore(
    SpriteSheet::from_colors(frame_width=2, frame_height=-1, pixels=[
      Some(red),
      Some(red),
    ]),
  )
}

///|
test "panic SpriteSheet::from_colors aborts on empty pixels" {
  ignore(SpriteSheet::from_colors(frame_width=2, frame_height=2, pixels=[]))
}

///|
test "panic SpriteSheet::from_colors aborts on length not a multiple" {
  // 5 pixels cannot tile 2x2 frames.
  ignore(
    SpriteSheet::from_colors(frame_width=2, frame_height=2, pixels=[
      Some(red),
      Some(red),
      Some(red),
      Some(red),
      Some(red),
    ]),
  )
}

///|
test "sprite fully inside writes exact pixels for the selected frame" {
  let sheet = sprite_fixture()
  let canvas = Canvas::new(width=4, height=4)
  canvas.sprite(sheet~, frame=0, x=1, y=1)
  inspect(wb_px(canvas, 1, 1), content="63488") // frame 0 top-left: red
  inspect(wb_px(canvas, 2, 1), content="2016") // frame 0 top-right: green
  inspect(wb_px(canvas, 1, 2), content="31") // frame 0 bottom-left: blue
  inspect(wb_px(canvas, 2, 2), content="65535") // frame 0 bottom-right: white
  // Neighbors outside the 2x2 destination stay untouched.
  inspect(wb_px(canvas, 0, 1), content="0")
  inspect(wb_px(canvas, 3, 1), content="0")
  inspect(wb_px(canvas, 1, 0), content="0")
  inspect(wb_px(canvas, 1, 3), content="0")
  inspect(wb_count(canvas, red), content="1")
  inspect(wb_count(canvas, green), content="1")
  inspect(wb_count(canvas, blue), content="1")
  inspect(wb_count(canvas, white), content="1")
}

///|
test "sprite frame selection reads the right row-major frame block" {
  let sheet = sprite_fixture()
  let frame0 = Canvas::new(width=4, height=4)
  frame0.sprite(sheet~, frame=0, x=0, y=0)
  let frame2 = Canvas::new(width=4, height=4)
  frame2.sprite(sheet~, frame=2, x=0, y=0)
  // Frame 2 mirrors frame 0, so every destination pixel must differ.
  inspect(wb_px(frame0, 0, 0), content="63488")
  inspect(wb_px(frame0, 1, 0), content="2016")
  inspect(wb_px(frame0, 0, 1), content="31")
  inspect(wb_px(frame0, 1, 1), content="65535")
  inspect(wb_px(frame2, 0, 0), content="65535")
  inspect(wb_px(frame2, 1, 0), content="31")
  inspect(wb_px(frame2, 0, 1), content="2016")
  inspect(wb_px(frame2, 1, 1), content="63488")
}

///|
test "sprite clips to the visible part past the left edge" {
  let canvas = Canvas::new(width=4, height=4)
  canvas.sprite(sheet=sprite_fixture(), frame=0, x=-1, y=1)
  // Only the right column of frame 0 is visible: green over white.
  inspect(wb_px(canvas, 0, 1), content="2016")
  inspect(wb_px(canvas, 0, 2), content="65535")
  inspect(wb_count(canvas, green), content="1")
  inspect(wb_count(canvas, white), content="1")
  inspect(wb_count(canvas, red), content="0")
  inspect(wb_count(canvas, blue), content="0")
  inspect(wb_px(canvas, 1, 1), content="0")
}

///|
test "sprite clips to the visible part past the right edge" {
  let canvas = Canvas::new(width=4, height=4)
  canvas.sprite(sheet=sprite_fixture(), frame=0, x=3, y=1)
  // Only the left column of frame 0 is visible: red over blue.
  inspect(wb_px(canvas, 3, 1), content="63488")
  inspect(wb_px(canvas, 3, 2), content="31")
  inspect(wb_count(canvas, red), content="1")
  inspect(wb_count(canvas, blue), content="1")
  inspect(wb_count(canvas, green), content="0")
  inspect(wb_count(canvas, white), content="0")
  inspect(wb_px(canvas, 2, 1), content="0")
}

///|
test "sprite clips to the visible part past the top edge" {
  let canvas = Canvas::new(width=4, height=4)
  canvas.sprite(sheet=sprite_fixture(), frame=0, x=1, y=-1)
  // Only the bottom row of frame 0 is visible: blue beside white.
  inspect(wb_px(canvas, 1, 0), content="31")
  inspect(wb_px(canvas, 2, 0), content="65535")
  inspect(wb_count(canvas, blue), content="1")
  inspect(wb_count(canvas, white), content="1")
  inspect(wb_count(canvas, red), content="0")
  inspect(wb_count(canvas, green), content="0")
  inspect(wb_px(canvas, 1, 1), content="0")
}

///|
test "sprite clips to the visible part past the bottom edge" {
  let canvas = Canvas::new(width=4, height=4)
  canvas.sprite(sheet=sprite_fixture(), frame=0, x=1, y=3)
  // Only the top row of frame 0 is visible: red beside green.
  inspect(wb_px(canvas, 1, 3), content="63488")
  inspect(wb_px(canvas, 2, 3), content="2016")
  inspect(wb_count(canvas, red), content="1")
  inspect(wb_count(canvas, green), content="1")
  inspect(wb_count(canvas, blue), content="0")
  inspect(wb_count(canvas, white), content="0")
  inspect(wb_px(canvas, 1, 2), content="0")
}

///|
test "sprite fully offscreen writes nothing, including edge touch" {
  let canvas = Canvas::new(width=4, height=4)
  canvas.sprite(sheet=sprite_fixture(), frame=0, x=-2, y=1) // entirely left
  canvas.sprite(sheet=sprite_fixture(), frame=0, x=4, y=1) // x == width
  canvas.sprite(sheet=sprite_fixture(), frame=0, x=1, y=-2) // entirely above
  canvas.sprite(sheet=sprite_fixture(), frame=0, x=1, y=4) // y == height
  canvas.sprite(sheet=sprite_fixture(), frame=0, x=-100, y=-100)
  canvas.sprite(sheet=sprite_fixture(), frame=0, x=1000, y=1000)
  inspect(wb_count(canvas, red), content="0")
  inspect(wb_count(canvas, green), content="0")
  inspect(wb_count(canvas, blue), content="0")
  inspect(wb_count(canvas, white), content="0")
  inspect(wb_count(canvas, black), content="16")
}

///|
test "sprite skips transparent pixels and never writes the sentinel" {
  let sheet = SpriteSheet::from_colors(frame_width=2, frame_height=2, pixels=[
    Some(red),
    None,
    None,
    Some(blue),
  ])
  let canvas = Canvas::new(width=4, height=4)
  canvas.clear(color=green)
  canvas.sprite(sheet~, frame=0, x=1, y=1)
  // Opaque pixels win; holes keep the green backdrop.
  inspect(wb_px(canvas, 1, 1), content="63488")
  inspect(wb_px(canvas, 2, 1), content="2016")
  inspect(wb_px(canvas, 1, 2), content="2016")
  inspect(wb_px(canvas, 2, 2), content="31")
  inspect(wb_count(canvas, green), content="14")
  // The -1 sentinel stays inside the sheet storage only.
  inspect(sprite_sentinel_count(canvas), content="0")
  inspect(sprite_px(sheet, 0, 1, 0), content="-1")
}

///|
test "sprite ignores out-of-range frame indices" {
  let canvas = Canvas::new(width=4, height=4)
  canvas.sprite(sheet=sprite_fixture(), frame=-1, x=0, y=0)
  canvas.sprite(sheet=sprite_fixture(), frame=3, x=0, y=0) // == frame_count
  canvas.sprite(sheet=sprite_fixture(), frame=1000000, x=0, y=0)
  inspect(wb_count(canvas, red), content="0")
  inspect(wb_count(canvas, green), content="0")
  inspect(wb_count(canvas, blue), content="0")
  inspect(wb_count(canvas, white), content="0")
  inspect(wb_count(canvas, black), content="16")
}

///|
test "sprite overwrites existing canvas pixels where opaque" {
  let canvas = Canvas::new(width=4, height=4)
  canvas.fill_rect(x=0, y=0, w=4, h=4, color=red)
  canvas.sprite(sheet=sprite_fixture(), frame=0, x=1, y=1)
  // 12 cells keep the red backdrop; the 4 sprite cells show frame 0,
  // whose top-left pixel is itself red.
  inspect(wb_count(canvas, red), content="13")
  inspect(wb_count(canvas, green), content="1")
  inspect(wb_count(canvas, blue), content="1")
  inspect(wb_count(canvas, white), content="1")
}
