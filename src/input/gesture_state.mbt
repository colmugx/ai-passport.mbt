///|
/// Shared Web-host gesture thresholds. The FoloToy Host consumes its pinned
/// BSP's recognized events, while Web uses this state machine over key edges.
pub const DOUBLE_CLICK_WINDOW_US : Int64 = 300_000L

///|
pub const LONG_PRESS_US : Int64 = 1_500_000L

///|
priv struct GestureKey {
  mut held : Bool
  mut down_at : Int64
  mut pending_click_at : Int64?
  mut second_down : Bool
  mut long_sent : Bool
}

///|
fn GestureKey::new() -> GestureKey {
  {
    held: false,
    down_at: 0L,
    pending_click_at: None,
    second_down: false,
    long_sent: false,
  }
}

///|
/// Per-button gesture recognition. Distinct buttons are independent, so two
/// simultaneous Web keys cannot cancel or combine each other's actions.
pub struct GestureState {
  priv up : GestureKey
  priv down : GestureKey
  priv ok : GestureKey
  priv mut last_now_us : Int64
}

///|
pub fn GestureState::new() -> GestureState {
  {
    up: GestureKey::new(),
    down: GestureKey::new(),
    ok: GestureKey::new(),
    last_now_us: 0L,
  }
}

///|
fn GestureState::slot(self : GestureState, button : Button) -> GestureKey {
  match button {
    Up => self.up
    Down => self.down
    Ok => self.ok
  }
}

///|
fn GestureState::check_time(self : GestureState, now_us : Int64) -> Unit {
  if now_us < self.last_now_us {
    abort("GestureState received a non-monotonic timestamp")
  }
  self.last_now_us = now_us
}

///|
/// Applies one press or release edge. Repeated identical edges are ignored.
/// `emit` receives only recognized events; callers deliver legacy edges
/// separately when this method returns `true`.
pub fn GestureState::input(
  self : GestureState,
  button : Button,
  pressed : Bool,
  now_us : Int64,
  emit : (Button, ButtonEvent) -> Unit,
) -> Bool {
  self.check_time(now_us)
  let key = self.slot(button)
  if pressed {
    if key.held {
      return false
    }
    match key.pending_click_at {
      Some(at) if now_us - at > DOUBLE_CLICK_WINDOW_US => {
        emit(button, Click)
        key.pending_click_at = None
      }
      _ => ()
    }
    key.second_down = key.pending_click_at is Some(_)
    key.held = true
    key.down_at = now_us
    key.long_sent = false
    emit(button, Press)
    true
  } else {
    if !key.held {
      return false
    }
    key.held = false
    if key.long_sent || now_us - key.down_at >= LONG_PRESS_US {
      if key.second_down {
        emit(button, Click)
        key.pending_click_at = None
      }
      if !key.long_sent {
        emit(button, LongPress)
      }
    } else if key.second_down {
      emit(button, DoubleClick)
      key.pending_click_at = None
    } else {
      key.pending_click_at = Some(now_us)
    }
    key.second_down = false
    true
  }
}

///|
/// Emits a long press once at its threshold and a single click only after
/// the double-click window has elapsed without a second short press.
pub fn GestureState::advance(
  self : GestureState,
  now_us : Int64,
  emit : (Button, ButtonEvent) -> Unit,
) -> Unit {
  self.check_time(now_us)
  for button in [Up, Down, Ok] {
    let key = self.slot(button)
    if key.held && !key.long_sent && now_us - key.down_at >= LONG_PRESS_US {
      if key.second_down {
        emit(button, Click)
        key.pending_click_at = None
        key.second_down = false
      }
      key.long_sent = true
      emit(button, LongPress)
    }
    if !key.held {
      match key.pending_click_at {
        Some(at) if now_us - at > DOUBLE_CLICK_WINDOW_US => {
          emit(button, Click)
          key.pending_click_at = None
        }
        _ => ()
      }
    }
  }
}
