// Whitebox tests: pin the procedural sprite builders' contracts (private
// pixel generation and the private tree sheets).

///|
test "the four walker frames are pairwise distinct" {
  let frames = [
    walker_frame_pixels(phase=0),
    walker_frame_pixels(phase=1),
    walker_frame_pixels(phase=2),
    walker_frame_pixels(phase=3),
  ]
  for a in 0..<4 {
    for b in (a + 1)..<4 {
      assert_true(frames[a] != frames[b], msg="frames \{a} and \{b} identical")
    }
  }
}

///|
test "every walker frame is a full 12x20 grid with transparent margins" {
  for phase in 0..<4 {
    let pixels = walker_frame_pixels(phase~)
    assert_eq(pixels.length(), 12 * 20)
    // The silhouette spans the full height (crown at row 0, feet at row
    // 19) but the outermost columns stay transparent on every pose.
    for y in 0..<20 {
      assert_true(pixels[y * 12] is None, msg="left border painted")
      assert_true(pixels[y * 12 + 11] is None, msg="right border painted")
    }
  }
}

///|
test "tree sheets are three private one-frame sheets in distinct sizes" {
  let state = State::new()
  inspect(state.tree_sheets.length(), content="3")
  let small = build_tree_sheet(width=8, height=14)
  let mid = build_tree_sheet(width=10, height=16)
  let tall = build_tree_sheet(width=12, height=20)
  for sheet in [small, mid, tall] {
    inspect(sheet.frame_count(), content="1")
  }
  assert_eq(small.frame_width(), 8)
  assert_eq(small.frame_height(), 14)
  assert_eq(mid.frame_width(), 10)
  assert_eq(mid.frame_height(), 16)
  assert_eq(tall.frame_width(), 12)
  assert_eq(tall.frame_height(), 20)
}
