# Sound resources and APSB v1

The SDK accepts audio only as externally prepared, headerless signed PCM16
little-endian, mono, 16000 Hz files. It does not decode WAV, MP3, Ogg, MIDI or
other authoring formats, and it does not resample. Because PCM is headerless,
the CLI can validate existence, containment, `.pcm`, non-empty content and an
even byte length, but it cannot verify the sample rate or channel count.

Sound declarations are independent from ordinary bundled assets:

```toml
[[sounds]]
name = "ambient_walk"
source = "assets/ambient_walk.pcm"

[[sounds]]
name = "jump"
source = "assets/jump.pcm"
```

The declaration order assigns Sound IDs starting at zero. The same pure
metadata compiler derives MoonBit symbols and serializes the runtime bank, so
generated source and bank indexes cannot use different ordering rules. Names
must begin with an ASCII letter and contain only ASCII letters, digits and
underscores; empty underscore-separated segments are rejected. Each segment's
first letter is uppercased for the generated symbol, and collisions after that
transformation are rejected.

## Typed MoonBit mapping

An application owns a small `<source-root>/sounds/moon.pkg`; the generated
`generated.mbt` beside it is ignored and never edited. For the conventional
`source = "src"` layout, use:

```gitignore
src/sounds/generated.mbt
```

```moonbit
import {
  "colmugx/ai-passport/audio" @audio,
}

rule(
  name: "passport-sounds",
  command: "passport generate-sounds --project . --output $output",
)

dev_build(
  rule: "passport-sounds",
  input: "../../passport.toml",
  output: "generated.mbt",
)
```

Moon resolves `dev_build` input and output paths from the package directory,
while the command runs from the module root. If packages live directly at the
module root, the input is `../passport.toml`. The co-versioned `passport` CLI
must be on `PATH`, just as it is for Host builds.

The Rule runs automatically before `moon check`, `moon build`, and `moon test`.
It emits a typed enum implementing `@audio.Sound`, so application code imports
its module package as `@sounds` and writes constructors such as
`@sounds.AmbientWalk` or `@sounds.Jump`. Adding, deleting, or renaming a
`[[sounds]]` entry updates the constructors without a manually run script.

The Rule depends on `passport.toml` because generated types depend only on
ordered metadata. Final `passport build` still reads and validates every PCM
file and emits the bank. Both paths call the same metadata compiler, so symbol
and ID ordering cannot drift. Metadata validation completes before the output
is written, so a metadata error preserves the previous valid mapping.

Playback properties are not resource metadata. `loop`, `autoplay`, `volume`,
`channel`, `pcmLoop` and every other undeclared field are rejected in a sound
table.

## Binary format

All integers are little-endian. Offsets are absolute byte offsets from the
start of the bank. IDs are implicit entry ordinals; names and application
semantics are not stored in the bank.

```text
APSB v1 header (16 bytes)
  0x00  char[4]  magic = "APSB"
  0x04  u16      version = 1
  0x06  u16      header_size = 16
  0x08  u32      entry_count
  0x0c  u16      entry_size = 8
  0x0e  u16      flags = 0

entry[entry_count] (8 bytes each)
  +0x00 u32      absolute payload offset
  +0x04 u32      PCM sample count

payload
  contiguous raw PCM16 LE bytes in entry order
```

The v1 writer limits the complete bank to `0x7fffffff` bytes for portable
MoonBit and 32-bit Host handling. Payloads must begin immediately after the
index, be non-empty, be contiguous in declaration order and consume the
remainder of the file exactly. Parsers reject bad magic/version/sizes/flags,
truncated indexes or payloads, empty payloads, non-contiguous offsets,
out-of-range values and trailing bytes.

A project with no sounds has a valid 16-byte bank with `entry_count = 0`.
Both Web and device builds write the exact compiler output as `sounds.bank`.
Host runtime consumption is introduced separately; APSB contains resources,
not a public mixer, codec or future streaming contract.
