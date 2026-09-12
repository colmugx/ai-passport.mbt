///|
test "Meter::six_eight is 6 eighth-note beats per bar" {
  debug_inspect(
    @music.Meter::six_eight(),
    content="{ numerator: 6, denominator: 8 }",
  )
}
