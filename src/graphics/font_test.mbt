// Blackbox tests: public text metrics and no-panic behavior only, no
// internal access. Docstring examples in font.mbt run as additional tests.

///|
test "text metrics constants" {
  inspect(@graphics.CHAR_ADVANCE, content="5")
  inspect(@graphics.LINE_HEIGHT, content="6")
}

///|
test "text_width of single and multi character lines" {
  inspect(@graphics.text_width(text="A"), content="4")
  inspect(@graphics.text_width(text="AB"), content="9")
  inspect(@graphics.text_width(text="HELLO"), content="24")
}

///|
test "text_width of empty text is zero" {
  inspect(@graphics.text_width(text=""), content="0")
}

///|
test "text_width takes the widest newline-separated line" {
  inspect(@graphics.text_width(text="AB\nCD"), content="9")
  inspect(@graphics.text_width(text="AB\nCDEF"), content="19")
  inspect(@graphics.text_width(text="CDEF\nAB"), content="19")
  inspect(@graphics.text_width(text="\n"), content="0")
  inspect(@graphics.text_width(text="AB\n"), content="9")
}

///|
test "text_height counts newline-separated lines with a minimum of one" {
  inspect(@graphics.text_height(text=""), content="6")
  inspect(@graphics.text_height(text="A"), content="6")
  inspect(@graphics.text_height(text="A\nB"), content="12")
  inspect(@graphics.text_height(text="A\n\nB"), content="18")
  inspect(@graphics.text_height(text="\n"), content="12")
}

///|
test "lowercase has the same metrics as uppercase" {
  inspect(@graphics.text_width(text="hello"), content="24")
  inspect(@graphics.text_width(text="HELLO"), content="24")
  inspect(@graphics.text_height(text="hello\nworld"), content="12")
}

///|
test "unknown characters count as one advance" {
  inspect(@graphics.text_width(text="~"), content="4")
  inspect(@graphics.text_width(text="A~B"), content="14")
  inspect(@graphics.text_width(text="~~~"), content="14")
}

///|
test "space counts toward width like any character" {
  inspect(@graphics.text_width(text=" "), content="4")
  inspect(@graphics.text_width(text="A B"), content="14")
}

///|
test "supported symbols measure as normal glyphs" {
  inspect(@graphics.text_width(text="-:%.!"), content="24")
  inspect(@graphics.text_width(text="12:00"), content="24")
  inspect(@graphics.text_height(text="-:%.!"), content="6")
}

///|
test "arbitrary unicode text never panics and just advances" {
  let canvas = @graphics.Canvas::new(width=30, height=20)
  let white = @core.Color::rgb(r=255, g=255, b=255)
  canvas.text(text="日本語 🎮 💥", x=2, y=2, color=white)
  canvas.text(text="🎮\n💥", x=0, y=0, color=white)
  canvas.text(text="", x=0, y=0, color=white)
  // Unknown characters count one per Unicode scalar value.
  inspect(@graphics.text_width(text="🎮"), content="4")
  inspect(@graphics.text_width(text="日本"), content="9")
  inspect(@graphics.text_height(text="🎮\n💥"), content="12")
}

///|
test "text at extreme coordinates never panics" {
  let canvas = @graphics.Canvas::new(width=30, height=20)
  let white = @core.Color::rgb(r=255, g=255, b=255)
  canvas.text(text="HELLO", x=-1000000, y=-1000000, color=white)
  canvas.text(text="HELLO\nWORLD", x=1000000, y=1000000, color=white)
  canvas.text(text="A", x=2147483647, y=2147483647, color=white)
  canvas.text(text="A", x=-2147483647, y=-2147483647, color=white)
}
