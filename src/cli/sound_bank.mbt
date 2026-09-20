///|
/// `APSB` sound bank v1 is deliberately small and application-agnostic.
/// Every integer is little endian. The 16-byte header is:
///
/// - bytes 0..4: ASCII `APSB`
/// - u16 version (1)
/// - u16 header size (16)
/// - u32 entry count
/// - u16 entry size (8)
/// - u16 flags (0)
///
/// Each entry is an absolute u32 byte offset followed by a u32 sample count.
/// Sound IDs are entry ordinals. Payloads are contiguous PCM16 LE bytes.
pub const SOUND_BANK_VERSION : Int = 1

///|
pub const SOUND_BANK_HEADER_SIZE : Int = 16

///|
pub const SOUND_BANK_ENTRY_SIZE : Int = 8

///|
/// Co-versioned bank filename emitted for every Host, including an empty bank
/// for projects that declare no sounds.
pub const SOUND_BANK_FILE : String = "sounds.bank"

///|
const SOUND_BANK_MAX_SIZE : Int64 = 0x7fff_ffffL

///|
/// Filesystem-free compiler input. The caller owns path resolution and file
/// reads; this layer owns every metadata, PCM and wire-format invariant.
pub(all) struct SoundInput {
  entry : SoundEntry
  pcm : Bytes
} derive(Eq, Debug)

///|
/// One validated declaration in the source-of-truth sound metadata mapping.
/// IDs and symbols are shared by generated MoonBit bindings and sound banks.
pub(all) struct SoundMetadata {
  id : Int
  name : String
  symbol : String
  source : String
} derive(Eq, Debug)

///|
/// One validated sound and its exact location in the emitted bank.
pub(all) struct CompiledSound {
  id : Int
  name : String
  symbol : String
  source : String
  offset : Int
  sample_count : Int
} derive(Eq, Debug)

///|
/// The single compiler result consumed by generated mappings and all Hosts.
pub(all) struct SoundCompilation {
  sounds : Array[CompiledSound]
  bank : Bytes
} derive(Eq, Debug)

///|
priv struct SoundMetadataCompiler {
  names : Set[String]
  symbols : Set[String]
  sounds : Array[SoundMetadata]
}

///|
fn sound_symbol(name : String) -> String raise {
  guard name != "" else {
    fail_cli("passport.toml: sound name must not be empty")
  }
  let symbol = StringBuilder(size_hint=name.length())
  let ends_at_segment_start = name.fold(init=true, fn(segment_start, ch) raise {
    if ch == '_' {
      guard !segment_start else {
        fail_cli(
          "passport.toml: sound name \"\{name}\" contains an empty segment",
        )
      }
      true
    } else {
      guard ch.is_ascii_alphabetic() || ch.is_ascii_digit() else {
        fail_cli(
          "passport.toml: sound name \"\{name}\" must contain only ASCII letters, digits and underscores",
        )
      }
      if symbol.is_empty() {
        guard ch.is_ascii_alphabetic() else {
          fail_cli(
            "passport.toml: sound name \"\{name}\" must begin with an ASCII letter",
          )
        }
      }
      symbol.write_char(
        if segment_start {
          ch.to_ascii_uppercase()
        } else {
          ch
        },
      )
      false
    }
  })
  guard !ends_at_segment_start else {
    fail_cli("passport.toml: sound name \"\{name}\" contains an empty segment")
  }
  symbol.to_string()
}

///|
fn SoundMetadataCompiler::new(capacity : Int) -> SoundMetadataCompiler {
  {
    names: Set([], capacity~),
    symbols: Set([], capacity~),
    sounds: Array(capacity~),
  }
}

///|
fn SoundMetadataCompiler::add(
  self : SoundMetadataCompiler,
  entry : SoundEntry,
) -> SoundMetadata raise {
  guard self.names.add_and_check(entry.name) else {
    fail_cli("duplicate sound name \"\{entry.name}\"")
  }
  guard entry.source.has_suffix(".pcm") else {
    fail_cli(
      "sound \"\{entry.name}\" source must use the .pcm extension: \{entry.source}",
    )
  }
  let symbol = sound_symbol(entry.name)
  guard self.symbols.add_and_check(symbol) else {
    fail_cli(
      "sound names collide after MoonBit symbol generation: \"\{symbol}\"",
    )
  }
  let sound : SoundMetadata = {
    id: self.sounds.length(),
    name: entry.name,
    symbol,
    source: entry.source,
  }
  self.sounds.push(sound)
  sound
}

///|
/// Validates declarations and produces the exact IDs and MoonBit symbols used
/// by both generated source and bank compilation. This is the single metadata
/// compiler; neither Rule integration nor Host builds reimplement its rules.
pub fn compile_sound_metadata(
  entries : Array[SoundEntry],
) -> Array[SoundMetadata] raise {
  let compiler = SoundMetadataCompiler::new(entries.length())
  entries.each(fn(entry) raise { ignore(compiler.add(entry)) })
  compiler.sounds
}

///|
/// Validates sound metadata and PCM bytes, assigns declaration-order IDs and
/// emits one deterministic APSB v1 bank. Headerless PCM cannot prove sample
/// rate or channel count; callers must supply PCM16 LE mono 16000 Hz data.
pub fn compile_sounds(inputs : Array[SoundInput]) -> SoundCompilation raise {
  let count = inputs.length()
  let payload_offset = SOUND_BANK_HEADER_SIZE.to_int64() +
    count.to_int64() * SOUND_BANK_ENTRY_SIZE.to_int64()
  guard payload_offset <= SOUND_BANK_MAX_SIZE else {
    fail_cli("sound bank exceeds the portable v1 size limit")
  }
  let metadata = SoundMetadataCompiler::new(count)
  let sounds : Array[CompiledSound] = []
  let total_size = for input in inputs; offset = payload_offset {
    let resource = metadata.add(input.entry)
    guard !input.pcm.is_empty() else {
      fail_cli("sound \"\{input.entry.name}\" PCM file must not be empty")
    }
    guard input.pcm.length() % 2 == 0 else {
      fail_cli("sound \"\{input.entry.name}\" PCM byte length must be even")
    }
    let sample_count = input.pcm.length() / 2
    sounds.push({
      id: resource.id,
      name: resource.name,
      symbol: resource.symbol,
      source: resource.source,
      offset: offset.to_int(),
      sample_count,
    })
    let next = offset + input.pcm.length().to_int64()
    guard next <= SOUND_BANK_MAX_SIZE else {
      fail_cli("sound bank exceeds the portable v1 size limit")
    }
    continue next
  } nobreak {
    offset.to_int()
  }

  let out = @buffer.Buffer(size_hint=total_size)
  out.write_byte(0x41)
  out.write_byte(0x50)
  out.write_byte(0x53)
  out.write_byte(0x42)
  out.write_uint16_le(SOUND_BANK_VERSION.to_uint16())
  out.write_uint16_le(SOUND_BANK_HEADER_SIZE.to_uint16())
  out.write_int_le(count)
  out.write_uint16_le(SOUND_BANK_ENTRY_SIZE.to_uint16())
  out.write_uint16_le(0)
  sounds.each(fn(sound) {
    out.write_int_le(sound.offset)
    out.write_int_le(sound.sample_count)
  })
  inputs.each(fn(input) { out.write_bytes(input.pcm) })
  let bank = out.to_bytes()
  guard bank.length() == total_size else {
    fail_cli("internal sound bank size mismatch")
  }
  { sounds, bank, }
}
