# Graphics

The current Web and FoloToy Hosts expose a full **240×320** drawing surface.
Applications query `display_info()` and use `Canvas::for_display()` when the
active Host determines the dimensions. A future monochrome Host quantizes the
RGB565 presentation stream at its Host boundary. Lighting is optional:
`backlight_level()` returns `None` on panels without a light, and
`set_backlight(0..100)` returns `false` there.

## Public drawing API

```moonbit
// Canvas
Canvas::new(width~, height~)        // aborts on non-positive dimensions
Canvas::logical()                   // current default 240×320
Canvas::for_display()               // active Host dimensions
display_info()                      // width, height, monochrome, has_backlight
backlight_level()                   // Int?; None on an unlit panel
set_backlight(level)                // Bool; false on an unlit panel
canvas.width() / canvas.height()

// Primitives — clip-safe drawing
canvas.clear(color~)
canvas.pixel(x~, y~, color~)              // offscreen = no-op
canvas.line(x0~, y0~, x1~, y1~, color~)   // Bresenham; endpoint order irrelevant
canvas.rect(x~, y~, w~, h~, color~)       // 1px outline; zero/negative size = no-op
canvas.fill_rect(x~, y~, w~, h~, color~)

// Sprites — transparency is `None` in the public constructor
SpriteSheet::from_colors(frame_width~, frame_height~, pixels~ : Array[@core.Color?])
sheet.frame_width() / sheet.frame_height() / sheet.frame_count()
canvas.sprite(sheet~, frame~, x~, y~)     // frame out of range = silent no-op

// Bitmap text — built-in 4×5 monospace font
canvas.text(text~, x~, y~, color~)
text_width(text~) / text_height(text~)
CHAR_ADVANCE (5) / LINE_HEIGHT (6)
```

Text glyph set: `A–Z`, `0–9`, space, `-` `:` `%` `.` `!`. Lowercase renders as
uppercase; unknown characters advance one `CHAR_ADVANCE` drawing nothing;
`\n` breaks lines.

Do not expose framebuffer ownership, strip rendering, or display-controller details.

All primitives must clip safely. Tests include negative coordinates,
partially/fully offscreen objects, right/bottom edge, and zero-size rectangles.

Storage (private, invisible in the API): `Canvas` keeps one 16-bit RGB565
value per pixel in a `FixedArray[UInt16]` — half the memory of an `Int` array
on 32-bit targets, identical behavior on both supported targets. `SpriteSheet`
deliberately keeps a wider `FixedArray[Int]`: its `-1` transparency sentinel
needs a value outside `0..=65535`, and RGB565 has no spare 16-bit code point
(a magic color key or a side transparency bitmap would trade correctness or
blit efficiency for two bytes per small sprite pixel).

v0.1 text is bitmap text only. Asset conversion and application-specific art belong outside the SDK.

## Read-only presentation

Backends read finished frames through an opaque read-only view — the Canvas
pixel buffer stays private.

```moonbit
Canvas::frame_view()                     // zero-copy read-only view
frame.width() / frame.height()
frame.copy_rgb565_row(y~, out~) -> Int   // RGB565 row copy; returns samples written
```

- `copy_rgb565_row` edge behavior (defined, never panics): out-of-range `y`
  copies nothing and returns `0`; `out` shorter than width copies the fitting
  prefix and returns that count (backend compares with `width()` to detect
  truncation); `out` longer than width leaves surplus cells untouched.
- Lifetime: the view shares canvas storage and is valid only until the source
  Canvas is next mutated. Sinks consume synchronously inside `present` or copy
  what they need; no full-frame snapshot is taken per present.
- RGB565 is the canonical presentation format: backends receive the same quantized colors as `Color::to_rgb565()`. `DisplaySink::present(frame~ : @graphics.FrameView)` is the synchronous presentation seam.
