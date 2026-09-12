///|
/// Builds a one-note track for the given role name and waveform.
fn role_track(name : String, waveform : @music.Waveform) -> @music.Track {
  {
    instrument: { name, waveform, },
    notes: [{ pitch: @music.Pitch::from_midi(midi=72), eighths: 3, }],
  }
}

///|
test "Song::new accepts exactly four tracks" {
  let tracks = [
    role_track("Celesta", @music.Pulse12),
    role_track("Woodwind Lead", @music.Pulse25),
    role_track("Lyrical Strings", @music.Pulse50),
    role_track("Low Strings", @music.Triangle),
  ]
  let song = @music.Song::new(
    meter=@music.Meter::six_eight(),
    tempo=@music.Tempo::standard(),
    tracks~,
  )
  debug_inspect(song.tracks.length(), content="4")
}

///|
test "Song::new rejects a fifth track with TooManyVoices" {
  let tracks = [
    role_track("Celesta", @music.Pulse12),
    role_track("Woodwind Lead", @music.Pulse25),
    role_track("Lyrical Strings", @music.Pulse50),
    role_track("Low Strings", @music.Triangle),
    role_track("Extra Voice", @music.Noise),
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
test "showcase song with the four v0.1 roles round-trips through debug_inspect" {
  let celesta : @music.Track = {
    instrument: { name: "Celesta", waveform: @music.Pulse12, },
    notes: [
      { pitch: @music.Pitch::from_midi(midi=76), eighths: 1, },
      { pitch: @music.Pitch::from_midi(midi=79), eighths: 1, },
      { pitch: @music.Pitch::from_midi(midi=83), eighths: 1, },
    ],
  }
  let woodwind : @music.Track = {
    instrument: { name: "Woodwind Lead", waveform: @music.Pulse25, },
    notes: [
      { pitch: @music.Pitch::from_midi(midi=71), eighths: 3, },
      { pitch: None, eighths: 3, },
    ],
  }
  let strings : @music.Track = {
    instrument: { name: "Lyrical Strings", waveform: @music.Pulse50, },
    notes: [{ pitch: @music.Pitch::from_midi(midi=64), eighths: 6, }],
  }
  let bass : @music.Track = {
    instrument: { name: "Low Strings", waveform: @music.Triangle, },
    notes: [
      { pitch: @music.Pitch::from_midi(midi=40), eighths: 3, },
      { pitch: @music.Pitch::from_midi(midi=45), eighths: 3, },
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
      #|  tracks: [
      #|    {
      #|      instrument: { name: "Celesta", waveform: Pulse12 },
      #|      notes: [
      #|        { pitch: Some({ midi: 76 }), eighths: 1 },
      #|        { pitch: Some({ midi: 79 }), eighths: 1 },
      #|        { pitch: Some({ midi: 83 }), eighths: 1 },
      #|      ],
      #|    },
      #|    {
      #|      instrument: { name: "Woodwind Lead", waveform: Pulse25 },
      #|      notes: [
      #|        { pitch: Some({ midi: 71 }), eighths: 3 },
      #|        { pitch: None, eighths: 3 },
      #|      ],
      #|    },
      #|    {
      #|      instrument: { name: "Lyrical Strings", waveform: Pulse50 },
      #|      notes: [{ pitch: Some({ midi: 64 }), eighths: 6 }],
      #|    },
      #|    {
      #|      instrument: { name: "Low Strings", waveform: Triangle },
      #|      notes: [
      #|        { pitch: Some({ midi: 40 }), eighths: 3 },
      #|        { pitch: Some({ midi: 45 }), eighths: 3 },
      #|      ],
      #|    },
      #|  ],
      #|}
    ),
  )
}
