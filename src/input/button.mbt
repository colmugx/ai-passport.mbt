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
/// Explicitly promotes the derived `Debug` method to a regular method.
pub extend Button with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Explicitly promotes the derived `Eq` methods to regular methods.
pub extend Button with Eq::{not_equal, equal}

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

///|
/// Explicitly promotes the derived `Debug` method to a regular method.
pub extend ButtonEvent with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Explicitly promotes the derived `Eq` methods to regular methods.
pub extend ButtonEvent with Eq::{not_equal, equal}
