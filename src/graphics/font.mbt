///|
/// Horizontal advance per character: glyph width 4 + 1 spacing.
///
/// # Example
/// ```mbt check
/// test {
///   inspect(CHAR_ADVANCE, content="5")
/// }
/// ```
pub const CHAR_ADVANCE : Int = 5

///|
/// Vertical distance between text lines: glyph height 5 + 1 spacing.
///
/// # Example
/// ```mbt check
/// test {
///   inspect(LINE_HEIGHT, content="6")
/// }
/// ```
pub const LINE_HEIGHT : Int = 6

///|
/// Glyph cell width in pixels (private font geometry).
const GLYPH_WIDTH : Int = 4

///|
/// Glyph cell height in pixels (private font geometry).
const GLYPH_HEIGHT : Int = 5

///|
/// Built-in 4x5 bitmap font, one `Int` per glyph. Each value packs the five
/// glyph rows into 20 bits: four bits per row, top row first, most
/// significant bit leftmost, so a glyph reads naturally as five hex digits
/// (bit 19 is its top-left pixel). Index layout: 0..25 = A-Z, 26..35 = 0-9,
/// then the symbols `-` `:` `%` `.` `!`.
let glyph_table : FixedArray[Int] = FixedArray::from_array([
  0x69F99, // A  .##. #..# #### #..# #..#
   0xE9E9E, // B  ###. #..# ###. #..# ###.
   0x78887, // C  .### #... #... #... .###
   0xE999E, // D  ###. #..# #..# #..# ###.
   0xF8E8F, // E  #### #... ###. #... ####
   0xF8E88, // F  #### #... ###. #... #...
   0x68B96, // G  .##. #... #.## #..# .##.
   0x99F99, // H  #..# #..# #### #..# #..#
   0xE444E, // I  ###. .#.. .#.. .#.. ###.
   0x31196, // J  ..## ...# ...# #..# .##.
   0x9ACA9, // K  #..# #.#. ##.. #.#. #..#
   0x8888F, // L  #... #... #... #... ####
   0x9F999, // M  #..# #### #..# #..# #..#
   0x9DB99, // N  #..# ##.# #.## #..# #..#
   0x69996, // O  .##. #..# #..# #..# .##.
   0xE9E88, // P  ###. #..# ###. #... #...
   0x69997, // Q  .##. #..# #..# #..# .###
   0xE9EA9, // R  ###. #..# ###. #.#. #..#
   0x7861E, // S  .### #... .##. ...# ###.
   0xF4444, // T  #### .#.. .#.. .#.. .#..
   0x99996, // U  #..# #..# #..# #..# .##.
   0x99964, // V  #..# #..# #..# .##. .#..
   0x999F9, // W  #..# #..# #..# #### #..#
   0x99699, // X  #..# #..# .##. #..# #..#
   0x99644, // Y  #..# #..# .##. .#.. .#..
   0xF168F, // Z  #### ...# .##. #... ####
   0x69996, // 0  .##. #..# #..# #..# .##.
   0x4C44E, // 1  .#.. ##.. .#.. .#.. ###.
   0x6934F, // 2  .##. #..# ..## .#.. ####
   0xE161E, // 3  ###. ...# .##. ...# ###.
   0x99F11, // 4  #..# #..# #### ...# ...#
   0xF8E1E, // 5  #### #... ###. ...# ###.
   0x68E96, // 6  .##. #... ###. #..# .##.
   0xF1111, // 7  #### ...# ...# ...# ...#
   0x69696, // 8  .##. #..# .##. #..# .##.
   0x69716, // 9  .##. #..# .### ...# .##.
   0x00F00, // -  .... .... #### .... ....
   0x04040, // :  .... .#.. .... .#.. ....
   0x92481, // %  #..# ..#. .#.. #... ...#
   0x00008, // .  .... .... .... .... #...
   0x44404, // !  .#.. .#.. .#.. .... .#..
])

///|
/// Maps a character to its 20-bit glyph pattern; 0 means "advance only".
/// Lowercase letters fold onto their uppercase glyphs; space and any
/// character outside the glyph set return 0 and draw nothing.
fn glyph_of(ch : Char) -> Int {
  match ch {
    'A'..='Z' => glyph_table[ch.to_int() - 0x41]
    'a'..='z' => glyph_table[ch.to_int() - 0x61]
    '0'..='9' => glyph_table[26 + ch.to_int() - 0x30]
    '-' => glyph_table[36]
    ':' => glyph_table[37]
    '%' => glyph_table[38]
    '.' => glyph_table[39]
    '!' => glyph_table[40]
    _ => 0
  }
}

///|
/// Width of one line of `count` characters:
/// `(count - 1) * CHAR_ADVANCE + GLYPH_WIDTH`, or 0 for an empty line.
fn line_width(count : Int) -> Int {
  if count <= 0 {
    0
  } else {
    (count - 1) * CHAR_ADVANCE + GLYPH_WIDTH
  }
}

///|
/// Width in pixels of the widest line (split on '\n'):
/// `(line_len - 1) * CHAR_ADVANCE + 4` for a non-empty line, 0 for an empty
/// line. Space and unknown characters count like any other character.
///
/// # Example
/// ```mbt check
/// test {
///   inspect(text_width(text="HELLO"), content="24")
///   inspect(text_width(text="AB\nCD"), content="9")
///   inspect(text_width(text=""), content="0")
/// }
/// ```
pub fn text_width(text~ : String) -> Int {
  let mut widest = 0
  let mut count = 0
  for ch in text {
    if ch == '\n' {
      let w = line_width(count)
      if w > widest {
        widest = w
      }
      count = 0
    } else {
      count += 1
    }
  }
  let w = line_width(count)
  if w > widest {
    widest = w
  }
  widest
}

///|
/// Height in pixels: number of '\n'-split lines (minimum 1) times
/// LINE_HEIGHT.
///
/// # Example
/// ```mbt check
/// test {
///   inspect(text_height(text="A"), content="6")
///   inspect(text_height(text="A\nB"), content="12")
/// }
/// ```
pub fn text_height(text~ : String) -> Int {
  let mut lines = 1
  for ch in text {
    if ch == '\n' {
      lines += 1
    }
  }
  lines * LINE_HEIGHT
}

///|
/// Draws text with the built-in 4×5 bitmap font, glyph top-left anchored at
/// (x, y). Glyph set: A–Z, 0–9, space, and the symbols `-` `:` `%` `.` `!`.
/// Lowercase letters render as uppercase; space and unknown characters
/// advance one CHAR_ADVANCE drawing nothing; `\n` moves to the next line
/// (y += LINE_HEIGHT, x resets to the anchor x). Clip-safe per pixel.
///
/// # Example
/// ```mbt check
/// test {
///   let canvas = Canvas::new(width=30, height=20)
///   canvas.text(text="HI", x=2, y=3, color=@core.Color::rgb(r=255, g=255, b=255))
///   inspect(text_width(text="HI"), content="9")
/// }
/// ```
pub fn Canvas::text(
  self : Canvas,
  text~ : String,
  x~ : Int,
  y~ : Int,
  color~ : @core.Color,
) -> Unit {
  let value = color.to_rgb565().to_uint16()
  let pixels = self.pixels
  let width = self.width
  let height = self.height
  let mut cx = x
  let mut cy = y
  for ch in text {
    if ch == '\n' {
      // Next line: reset to the anchor column, drop one line height.
      cx = x
      cy = cy + LINE_HEIGHT
    } else {
      let pattern = glyph_of(ch)
      if pattern != 0 {
        for ry in 0..<GLYPH_HEIGHT {
          let row = (pattern >> ((GLYPH_HEIGHT - 1 - ry) * GLYPH_WIDTH)) & 0xF
          for rx in 0..<GLYPH_WIDTH {
            if (row & (1 << (GLYPH_WIDTH - 1 - rx))) != 0 {
              let px = cx + rx
              let py = cy + ry
              // Clip-safe per pixel: write only inside the canvas.
              if px >= 0 && px < width && py >= 0 && py < height {
                pixels[py * width + px] = value
              }
            }
          }
        }
      }
      cx = cx + CHAR_ADVANCE
    }
  }
}
