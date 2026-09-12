///|
/// Semantic buttons (AGENTS.md rule 5): `Up`, `Down` and `Ok` are the only
/// button values applications see. Backends map their physical inputs onto
/// these values; public app code never touches raw hardware signals.
pub(all) enum Button {
  Up
  Down
  Ok
} derive(Debug, Eq)

///|
/// Button events with the value set locked to the driver contract: `Press`,
/// `Click`, `DoubleClick` and `LongPress`. This package is data-only for
/// events — converting an event stream into an `InputState` belongs to the
/// backend adapter, not to this API.
pub(all) enum ButtonEvent {
  Press
  Click
  DoubleClick
  LongPress
} derive(Debug, Eq)
