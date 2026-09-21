///|
/// Test helper: build a `Rect` from its four fields.
fn rect(x : Int, y : Int, w : Int, h : Int) -> @core.Rect {
  { x, y, w, h, }
}

///|
test "Color::rgb clamps each component into 0..=255" {
  debug_inspect(@core.Color::rgb(r=0, g=0, b=0), content="{ r: 0, g: 0, b: 0 }")
  debug_inspect(
    @core.Color::rgb(r=255, g=255, b=255),
    content="{ r: 255, g: 255, b: 255 }",
  )
  debug_inspect(
    @core.Color::rgb(r=-1, g=-128, b=-100000),
    content="{ r: 0, g: 0, b: 0 }",
  )
  debug_inspect(
    @core.Color::rgb(r=256, g=999, b=1000000),
    content="{ r: 255, g: 255, b: 255 }",
  )
}

///|
test "Color::to_rgb565 matches the pinned encodings" {
  inspect(@core.Color::rgb(r=255, g=255, b=255).to_rgb565(), content="65535")
  inspect(@core.Color::rgb(r=255, g=0, b=0).to_rgb565(), content="63488")
  inspect(@core.Color::rgb(r=0, g=255, b=0).to_rgb565(), content="2016")
  inspect(@core.Color::rgb(r=0, g=0, b=255).to_rgb565(), content="31")
  inspect(@core.Color::rgb(r=0, g=0, b=0).to_rgb565(), content="0")
}

///|
test "Color::to_rgb565 quantization boundaries" {
  // Smallest value below the first step of every channel quantizes to 0.
  inspect(@core.Color::rgb(r=7, g=3, b=7).to_rgb565(), content="0")
  // First step of every channel: r5=1, g6=1, b5=1.
  inspect(@core.Color::rgb(r=8, g=4, b=8).to_rgb565(), content="2081")
}

///|
test "Rect::contains is left/top inclusive and right/bottom exclusive" {
  let r = rect(2, 3, 10, 20)
  inspect(r.contains(x=2, y=3), content="true") // left/top inclusive
  inspect(r.contains(x=11, y=22), content="true") // last inside pixel
  inspect(r.contains(x=12, y=3), content="false") // right edge exclusive
  inspect(r.contains(x=2, y=23), content="false") // bottom edge exclusive
  inspect(r.contains(x=1, y=3), content="false")
  inspect(r.contains(x=2, y=2), content="false")
  inspect(r.contains(x=7, y=13), content="true")
}

///|
test "Rect::contains with zero-size and negative-coordinate rects" {
  let zero = rect(5, 5, 0, 0)
  inspect(zero.contains(x=5, y=5), content="false")
  let empty_by_height = rect(0, 0, 10, 0)
  inspect(empty_by_height.contains(x=0, y=0), content="false")
  let negative = rect(-10, -10, 5, 5)
  inspect(negative.contains(x=-10, y=-10), content="true")
  inspect(negative.contains(x=-6, y=-6), content="true")
  inspect(negative.contains(x=-5, y=-5), content="false")
  inspect(negative.contains(x=-11, y=-8), content="false")
}

///|
test "Rect::intersects and intersection on disjoint rects" {
  let a = rect(0, 0, 10, 10)
  let b = rect(20, 20, 5, 5)
  inspect(a.intersects(other=b), content="false")
  inspect(b.intersects(other=a), content="false")
  debug_inspect(a.intersection(other=b), content="None")
  debug_inspect(b.intersection(other=a), content="None")
}

///|
test "partial overlap is symmetric" {
  let a = rect(0, 0, 10, 10)
  let b = rect(5, 5, 10, 10)
  inspect(a.intersects(other=b), content="true")
  inspect(b.intersects(other=a), content="true")
  debug_inspect(
    a.intersection(other=b),
    content="Some({ x: 5, y: 5, w: 5, h: 5 })",
  )
  debug_inspect(
    b.intersection(other=a),
    content="Some({ x: 5, y: 5, w: 5, h: 5 })",
  )
}

///|
test "containment overlap returns the smaller rect" {
  let outer = rect(0, 0, 100, 100)
  let inner = rect(10, 10, 5, 5)
  inspect(inner.intersects(other=outer), content="true")
  debug_inspect(
    outer.intersection(other=inner),
    content="Some({ x: 10, y: 10, w: 5, h: 5 })",
  )
  debug_inspect(
    inner.intersection(other=outer),
    content="Some({ x: 10, y: 10, w: 5, h: 5 })",
  )
}

///|
test "edge-touching rects have zero-area overlap" {
  let a = rect(0, 0, 10, 10)
  let right = rect(10, 0, 10, 10)
  let bottom = rect(0, 10, 10, 10)
  inspect(a.intersects(other=right), content="false")
  inspect(a.intersects(other=bottom), content="false")
  debug_inspect(a.intersection(other=right), content="None")
  debug_inspect(a.intersection(other=bottom), content="None")
}

///|
test "empty participants never intersect" {
  let empty_w = rect(0, 0, 0, 10)
  let empty_h = rect(0, 0, 10, -1)
  let valid = rect(0, 0, 10, 10)
  inspect(empty_w.intersects(other=valid), content="false")
  inspect(valid.intersects(other=empty_w), content="false")
  inspect(empty_h.intersects(other=empty_h), content="false")
  debug_inspect(empty_w.intersection(other=valid), content="None")
  debug_inspect(valid.intersection(other=empty_h), content="None")
  debug_inspect(empty_h.intersection(other=empty_w), content="None")
}

///|
test "negative sizes are treated as empty, not normalized" {
  let flipped = rect(10, 10, -5, -5)
  inspect(flipped.contains(x=8, y=8), content="false")
  let valid = rect(0, 0, 100, 100)
  inspect(flipped.intersects(other=valid), content="false")
  inspect(valid.intersects(other=flipped), content="false")
  debug_inspect(flipped.intersection(other=valid), content="None")
  debug_inspect(valid.intersection(other=flipped), content="None")
}

///|
test "logical display constants match the core contract" {
  inspect(@core.LOGICAL_WIDTH, content="240")
  inspect(@core.LOGICAL_HEIGHT, content="320")
}

///|
test "public structs are externally constructible" {
  debug_inspect(@core.Point::{ x: 1, y: 2, }, content="{ x: 1, y: 2 }")
  debug_inspect(@core.Size::{ w: 3, h: 4, }, content="{ w: 3, h: 4 }")
  debug_inspect(
    @core.Color::{ r: 1, g: 2, b: 3, },
    content="{ r: 1, g: 2, b: 3 }",
  )
  debug_inspect(
    @core.Rect::{ x: 1, y: 2, w: 3, h: 4, },
    content="{ x: 1, y: 2, w: 3, h: 4 }",
  )
}
