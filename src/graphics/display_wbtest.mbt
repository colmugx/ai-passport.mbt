///|
test "display facts size the canvas and optional backlight updates" {
  let current = Ref(42)
  @display_runtime.install(
    @display_runtime.DisplayRuntime::new(
      width=17,
      height=29,
      monochrome=true,
      backlight_level=fn() { current.val },
      set_backlight=fn(level) { current.val = level },
    ),
  )
  let info = display_info()
  assert_eq(info.width, 17)
  assert_eq(info.height, 29)
  assert_true(info.monochrome)
  assert_true(info.has_backlight)
  let canvas = Canvas::for_display()
  assert_eq(canvas.width(), 17)
  assert_eq(canvas.height(), 29)
  assert_eq(backlight_level(), Some(42))
  assert_true(set_backlight(70))
  assert_eq(current.val, 70)
  current.val = -1
  assert_eq(backlight_level(), None)
  assert_true(!set_backlight(50))
  assert_eq(current.val, -1)
}
