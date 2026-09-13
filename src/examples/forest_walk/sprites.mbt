///|
/// Builds the walker's four-frame sprite sheet: four 12x20 poses generated
/// procedurally by `walker_frame_pixels`, one weight-shift beat each.
fn build_walker_sheet() -> @graphics.SpriteSheet {
  let pixels : Array[@core.Color?] = []
  for phase in 0..<4 {
    pixels.append(walker_frame_pixels(phase~))
  }
  @graphics.SpriteSheet::from_colors(frame_width=12, frame_height=20, pixels~)
}

///|
/// Generates one 12x20 walker pose as row-major pixels with `None` for the
/// surrounding transparency. The head and torso silhouette is fixed; the
/// legs carry the animation: even phases swing the legs apart (first the
/// left leg forward, then the right), odd phases pass with the legs
/// together and the non-weight-bearing leg bent at the knee. Placeholder
/// art — final walk-cycle art arrives in PR 6.
fn walker_frame_pixels(phase~ : Int) -> Array[@core.Color?] {
  let w = 12
  let h = 20
  let skin = @core.Color::rgb(r=224, g=180, b=148)
  let cloth = @core.Color::rgb(r=96, g=64, b=48)
  let boot = @core.Color::rgb(r=54, g=40, b=36)
  let p = phase % 4
  let swing = [2, 0, -2, 0][p]
  let left_dx = swing
  let right_dx = -swing
  // On the passing beats the weight lands on one straight leg while the
  // other bends and lifts its boot one row off the ground.
  let left_bent = p == 3
  let right_bent = p == 1
  // One leg below the hips: `base` is the hip column, the swing offset `dx`
  // grows toward the foot, and a bent leg keeps its boot at row 18.
  fn leg(base : Int, dx : Int, bent : Bool, x : Int, y : Int) -> @core.Color? {
    let off = dx * (y - 14) / 5
    if (!bent || y <= 18) && (x == base + off || x == base + off + 1) {
      Some(if y >= 18 { boot } else { cloth })
    } else {
      None
    }
  }
  fn at(x : Int, y : Int) -> @core.Color? {
    if y <= 4 {
      // Head: a rounded blob, narrower at the crown and the chin.
      let inset = if y == 0 || y == 4 { 1 } else { 0 }
      if x >= 3 + inset && x <= 8 - inset {
        Some(skin)
      } else {
        None
      }
    } else if y == 5 {
      // Neck.
      if x >= 5 && x <= 6 {
        Some(cloth)
      } else {
        None
      }
    } else if y <= 7 {
      // Shoulders.
      if x >= 3 && x <= 8 {
        Some(cloth)
      } else {
        None
      }
    } else if y <= 14 {
      // Torso and hips.
      if x >= 4 && x <= 7 {
        Some(cloth)
      } else {
        None
      }
      // Legs, rows 15..=19: the leg swinging forward is drawn on top where
      // the two cross.
    } else if left_dx >= right_dx {
      match leg(4, left_dx, left_bent, x, y) {
        Some(color) => Some(color)
        None => leg(6, right_dx, right_bent, x, y)
      }
    } else {
      match leg(6, right_dx, right_bent, x, y) {
        Some(color) => Some(color)
        None => leg(4, left_dx, left_bent, x, y)
      }
    }
  }
  let pixels : Array[@core.Color?] = []
  for y in 0..<h {
    for x in 0..<w {
      pixels.push(at(x, y))
    }
  }
  pixels
}

///|
/// Builds a one-frame tree sprite sheet of the given size.
fn build_tree_sheet(width~ : Int, height~ : Int) -> @graphics.SpriteSheet {
  @graphics.SpriteSheet::from_colors(
    frame_width=width,
    frame_height=height,
    pixels=tree_pixels(width~, height~),
  )
}

///|
/// Generates one tree as row-major pixels: a jagged triangular canopy with
/// a shaded right side over a short trunk, `None` around it.
fn tree_pixels(width~ : Int, height~ : Int) -> Array[@core.Color?] {
  let leaf = @core.Color::rgb(r=58, g=110, b=74)
  let leaf_shade = @core.Color::rgb(r=40, g=84, b=56)
  let bark = @core.Color::rgb(r=96, g=72, b=50)
  let trunk_h = (height / 5).max(2)
  let canopy_bottom = height - trunk_h - 1
  let center = (width - 1) / 2
  fn at(x : Int, y : Int) -> @core.Color? {
    if y <= canopy_bottom {
      // Canopy: the half-width grows toward the base and the outermost
      // pixel of every other diagonal is dropped for a jagged edge.
      let hw = (y + 1) * (width / 2 - 1) / (canopy_bottom + 1) + 1
      let spread = x - center
      if spread.abs() <= hw && !(spread.abs() == hw && (x + y) % 2 == 0) {
        Some(if spread > 0 { leaf_shade } else { leaf })
      } else {
        None
      }
    } else if x == center || x == center + 1 {
      // Trunk: two columns under the canopy tip.
      Some(bark)
    } else {
      None
    }
  }
  let pixels : Array[@core.Color?] = []
  for y in 0..<height {
    for x in 0..<width {
      pixels.push(at(x, y))
    }
  }
  pixels
}
