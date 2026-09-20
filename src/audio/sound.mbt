///|
/// A generated sound resource that resolves to its declaration-order ID in
/// `sounds.bank`. Application projects receive implementations through their
/// generated `@sounds.Sound` enum; they do not construct numeric IDs.
///
/// This trait describes only the current PCM resource capability. It does not
/// imply that every future audio source must live in a sound bank.
pub(open) trait Sound {
  /// The stable sound-bank entry ordinal generated from `passport.toml`.
  fn resource_id(Self) -> UInt
}
