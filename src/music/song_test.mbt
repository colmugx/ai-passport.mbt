///|
/// Builds a one-note track for the given instrument.
fn role_track(instrument : @music.Instrument) -> @music.Track {
  {
    instrument,
    notes: [{ pitch: @music.Pitch::from_midi(midi=72), ticks: 12, }],
  }
}

///|
/// A noise instrument for tests (no preset exists for the noise role).
fn noise_instrument() -> @music.Instrument {
  {
    name: "Extra Voice",
    waveform: @music.Noise,
    envelope: { attack_ms: 0, decay_ms: 30, sustain: 4096, release_ms: 32, },
    volume: 100,
    vibrato: None,
  }
}

///|
test "Song::new accepts exactly four tracks" {
  let tracks = [
    role_track(@music.Instrument::celesta()),
    role_track(@music.Instrument::woodwind()),
    role_track(@music.Instrument::strings()),
    role_track(@music.Instrument::low_strings()),
  ]
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks~,
  )
  debug_inspect(song.tracks.length(), content="4")
  debug_inspect(song.ticks_per_eighth, content="4")
}

///|
test "Song::new rejects a fifth track with TooManyVoices" {
  let tracks = [
    role_track(@music.Instrument::celesta()),
    role_track(@music.Instrument::woodwind()),
    role_track(@music.Instrument::strings()),
    role_track(@music.Instrument::low_strings()),
    role_track(noise_instrument()),
  ]
  try
    @music.Song::new(
      meter=@music.Meter::six_eight(),
      tempo=@music.Tempo::standard(),
      tracks~,
    )
  catch {
    err => inspect(err, content="TooManyVoices")
  } noraise {
    _ => fail("expected TooManyVoices")
  }
}

///|
test "Song::new allows zero tracks" {
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[],
  )
  debug_inspect(song.tracks.length(), content="0")
}

///|
test "Song::new defaults to 4 ticks per eighth and accepts overrides" {
  let track = role_track(@music.Instrument::celesta())
  let default = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[track],
  )
  debug_inspect(default.ticks_per_eighth, content="4")
  let fine = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[track],
    ticks_per_eighth=8,
  )
  debug_inspect(fine.ticks_per_eighth, content="8")
}

///|
test "panic Song::new rejects a zero tick resolution" {
  ignore(
    @music.Song::new(
      meter=@music.Meter::six_eight(),
      tempo=@music.Tempo::standard(),
      tracks=[],
      ticks_per_eighth=0,
    ),
  )
}

///|
test "showcase song with the four v0.1 roles round-trips through debug_inspect" {
  let celesta : @music.Track = {
    instrument: @music.Instrument::celesta(),
    notes: [
      { pitch: @music.Pitch::from_midi(midi=76), ticks: 4, },
      { pitch: @music.Pitch::from_midi(midi=79), ticks: 4, },
      { pitch: @music.Pitch::from_midi(midi=83), ticks: 4, },
    ],
  }
  let woodwind : @music.Track = {
    instrument: @music.Instrument::woodwind(),
    notes: [
      { pitch: @music.Pitch::from_midi(midi=71), ticks: 12, },
      { pitch: None, ticks: 12, },
    ],
  }
  let strings : @music.Track = {
    instrument: @music.Instrument::strings(),
    notes: [{ pitch: @music.Pitch::from_midi(midi=64), ticks: 24, }],
  }
  let bass : @music.Track = {
    instrument: @music.Instrument::low_strings(),
    notes: [
      { pitch: @music.Pitch::from_midi(midi=40), ticks: 12, },
      { pitch: @music.Pitch::from_midi(midi=45), ticks: 12, },
    ],
  }
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks=[celesta, woodwind, strings, bass],
  )
  debug_inspect(
    song,
    content=(
      #|{
      #|  meter: { numerator: 6, denominator: 8 },
      #|  tempo: { dotted_quarter_bpm: 76 },
      #|  ticks_per_eighth: 4,
      #|  tracks: [
      #|    {
      #|      instrument: {
      #|        name: "Celesta",
      #|        waveform: Pulse12,
      #|        envelope: { attack_ms: 0, decay_ms: 240, sustain: 4096, release_ms: 128 },
      #|        volume: 100,
      #|        vibrato: None,
      #|      },
      #|      notes: [
      #|        { pitch: Some({ midi: 76 }), ticks: 4 },
      #|        { pitch: Some({ midi: 79 }), ticks: 4 },
      #|        { pitch: Some({ midi: 83 }), ticks: 4 },
      #|      ],
      #|    },
      #|    {
      #|      instrument: {
      #|        name: "Woodwind Lead",
      #|        waveform: Pulse25,
      #|        envelope: { attack_ms: 1, decay_ms: 64, sustain: 57344, release_ms: 256 },
      #|        volume: 100,
      #|        vibrato: Some({ rate_millihz: 5000, depth_cents: 13 }),
      #|      },
      #|      notes: [{ pitch: Some({ midi: 71 }), ticks: 12 }, { pitch: None, ticks: 12 }],
      #|    },
      #|    {
      #|      instrument: {
      #|        name: "Lyrical Strings",
      #|        waveform: Pulse50,
      #|        envelope: { attack_ms: 64, decay_ms: 128, sustain: 57344, release_ms: 512 },
      #|        volume: 100,
      #|        vibrato: None,
      #|      },
      #|      notes: [{ pitch: Some({ midi: 64 }), ticks: 24 }],
      #|    },
      #|    {
      #|      instrument: {
      #|        name: "Low Strings",
      #|        waveform: Triangle,
      #|        envelope: { attack_ms: 16, decay_ms: 128, sustain: 49152, release_ms: 341 },
      #|        volume: 100,
      #|        vibrato: None,
      #|      },
      #|      notes: [
      #|        { pitch: Some({ midi: 40 }), ticks: 12 },
      #|        { pitch: Some({ midi: 45 }), ticks: 12 },
      #|      ],
      #|    },
      #|  ],
      #|}
    ),
  )
}
