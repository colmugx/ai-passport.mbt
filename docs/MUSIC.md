# Music

## SDK contract

`music` provides `Meter`, `Tempo`, `Pitch`, `Note`, `Instrument`, `Track`, `Song`, `Sequencer`, and `TickClock`. `audio` provides `Synth`, `Player`, and `PcmSink`. The v0.1 synthesis limit is four monophonic voices, rendered as 16000 Hz signed PCM16 mono. Waveforms are `Pulse12`, `Pulse25`, `Pulse50`, `Triangle`, and `Noise`. The instrument presets describe musical roles; applications choose their own compositions.

`Meter::six_eight()` and `Tempo::standard()` provide 6/8 and 76 dotted-quarter beats per minute. The tempo unit is the dotted quarter, so a 6/8 bar contains two beats.

## Timing model

Time is measured in **song ticks**: one eighth note lasts `ticks_per_eighth`
ticks (`Song.ticks_per_eighth`, v0.1 default 4). At the default resolution an
eighth = 4 ticks, a sixteenth = 2, a thirty-second = 1, and in 6/8 a dotted
quarter = 12 ticks. `Note.ticks`, sequencer positions, and loop bounds are
all in song ticks.

## Instrument model

The waveform is only the oscillator shape; articulation lives on the
`Instrument`:

```moonbit
Envelope { attack_ms, decay_ms, sustain, release_ms }  // ms at 16 kHz; sustain is a
                                                       // 0..65536 fixed-point fraction
Vibrato  { rate_millihz, depth_cents }                 // triangle LFO
Instrument { name, waveform, envelope, volume, vibrato? }
Instrument::celesta() / woodwind() / strings() / low_strings()
```

`volume` is 0..=100 percent of the voice peak (clamped by the synth). Preset
values replicate the historical per-waveform behavior, except that sub-ms
envelope times quantize (celesta's 4-sample attack becomes an instant
attack) and vibrato depth converts as `depth/1731` of the phase increment.
The synth derives ALL envelope/volume/vibrato state from the instrument —
never from the waveform.

Envelope durations quantize to samples at 16 samples/ms. Attack and decay use integer whole-step and remainder ramps, with their accumulated error reset at stage changes. Release derives its whole step and remainder when it begins, from the **current** envelope level and configured release duration. Gate exhaustion and `Synth::release` use that same entry path, so early release and release during attack or decay take the configured number of samples to reach zero. Zero-millisecond release is immediate. A positive long ramp continues even when its whole step is zero; it does not stall or end early.

## Public engine API

```moonbit
// transport (package music)
NoteOn { track, pitch, ticks, instrument }         // note-start event
Sequencer::new(song~) / new_with_loop(song~, start~, end~)
sequencer.tick() / length()
sequencer.step_into(FixedArray[NoteOn?]) -> Int    // realtime: caller-owned slots
sequencer.step() -> Array[NoteOn]                  // allocating convenience
// arrival-based transport; a tick is one song tick (1/32 note by default).
// length() is loop_end - loop_start; tick() stays in the loop region.

TickClock::new(sample_rate~, dotted_quarter_bpm~, ticks_per_eighth~)
// one tick must last >= 1 sample (aborts otherwise)
clock.pump(samples~) -> Int                        // exact fractional carry (Bresenham)
clock.ticks_to_samples(ticks~) -> Int              // nominal duration (floor)
clock.ticks_to_samples_exact(ticks~) -> Int        // phase-aware: to the future boundary
clock.samples_to_next_tick() -> Int                // segment length to the next boundary
// 16000 Hz, 76 dotted-quarter BPM, 4 ticks/eighth: first tick after 1053 samples.

// synthesis (package audio)
Synth::new()                                       // 4 monophonic voices
synth.trigger(voice~, on~ : NoteOn, gate_samples~)
synth.release(voice~)
synth.render(out~ : FixedArray[Int])               // PCM16 mix, clamp, zero-allocation
PcmSink (open trait) / BufferSink                  // bounded output contract + test double
```

`Song` is an **immutable snapshot**: `Song::new` deep-copies the caller's
tracks array and every track's notes array, so mutating authoring arrays
after construction can never change the song — nor invalidate a sequencer
cursor walk or a player's event scratch capacity, both sized from the
snapshot at construction. Every field is private; read accessors are
`Song::meter()`, `Song::tempo()`, `Song::ticks_per_eighth()` and
`Song::track_count()`; no track arrays are exposed. `Track` and `Note`
remain pub(all) authoring value types.

## Transport and loops

The sequencer transport is **arrival-based**: `step()` moves the transport
onto the next song tick and reports the note-starts whose start boundary is
the tick it lands on. The four arrival kinds behave uniformly:

1. **Initial tick 0** — a fresh sequencer sits on tick 0 with its note starts
   unfired; its first `step()` is the arrival at tick 0 (`tick()` stays 0).
   An audio player calls it before rendering its first sample. A note at
   tick 0 starts at output sample 0, subject to its envelope attack.
2. **Normal boundaries** — each later `step()` arrives at the next tick and
   fires the note-starts beginning there, exactly on the boundary sample.
3. **Loop wrap** — when the transport would move onto `loop_end`, it wraps
   to `loop_start` on that boundary and the wrapped arrival fires the
   note-starts that begin at `loop_start`.
4. **loop_start events** — starts exactly at `loop_start` re-fire on every
   wrap; a wrap landing mid-note (consumed > 0) stays silent; starts before
   `loop_start` never repeat; notes crossing the loop end finish with the
   gate length they were triggered with.

The initial tick-0 arrival moves the transport nothing, so it never counts a
beat.

Realtime contract: `step_into(events : FixedArray[NoteOn?]) -> Int` delivers
the arrival's note starts through a caller-owned buffer (at least one slot
per track, aborting otherwise) and allocates nothing — the path a player
uses every tick. `step()` is the allocating convenience wrapper for tests
and offline timing math.

## Gate timing

Note gates use `TickClock::ticks_to_samples_exact(ticks~)`: the exact sample
distance from the clock's **current phase** (the fractional carry right after
a boundary) to the boundary `ticks` ticks in the future — the sum of the next
`ticks` boundary segments. A note of `ticks` song ticks therefore releases
exactly on the boundary `ticks` ticks after its start, whatever the carry.
`ticks_to_samples` remains as the phase-independent *nominal* duration
(`floor(ticks * num / den)`). One song tick must last at least one sample
(`TickClock::new` aborts otherwise): the segment-based transport has no
sample-accurate meaning below that.

## Player and real-time rendering

`Player` (package audio) owns the authoritative transport:

```text
Song -> TickClock -> Sequencer -> NoteOn -> Synth -> PCM16
```

```moonbit
Player::new(song~)                    // whole song loops, 16000 Hz baseline
player.render(out~)                   // sample-accurate: note starts fire at their
                                      // exact sample offset inside the buffer
player.pause() / unpause() / paused()
player.position_ticks() / beat()      // graphics reads these for animation sync
```

`render` segments each buffer at tick boundaries (via `Synth::render_range`
and `TickClock::samples_to_next_tick`): render up to the boundary, step the
sequencer, trigger the new notes, continue. The transport starts ON tick 0:
the first unpaused render fires the tick-0 starts before its first sample.
Notes trigger with an exact phase-aware gate (see Gate timing above). Tested
invariants: a tick-0 note starts at output sample 0;
`render(4096)` equals 16 x `render(256)` sample-exactly across tick
boundaries and loop wraps; loop-start note events fire on the wrap boundary;
pause renders silence and freezes transport, note and loop state;
resume continues the never-paused stream exactly. Application/frame code
never pumps a clock or steps a sequencer — a backend feeds `render` from its
audio callback with real sample counts. (`unpause` because `resume` is a
reserved word on moon 0.1.20260904.)

`beat()` counts dotted-quarter beats from the player's authoritative sample clock. At each real sample boundary where `TickClock::pump` advances one tick in a non-empty song, the player adds that tick to its elapsed count. The count is independent of sequencer position and loop length, including a one-tick loop whose position is always zero. With the default twelve ticks per dotted-quarter beat, 12 elapsed ticks give beat 1 and 24 give beat 2. The initial tick-0 arrival consumes no time; an empty song remains at beat 0; pause freezes the count.

The player owns a preallocated `FixedArray[NoteOn?]` with one slot per snapshot track and calls `Sequencer::step_into` on arrivals. `Sequencer::step()` remains an allocating convenience API. Rendering output in different chunk sizes yields the same sample stream. Native and JS targets are tested. Host and device PCM sink implementations belong outside this reusable SDK.
