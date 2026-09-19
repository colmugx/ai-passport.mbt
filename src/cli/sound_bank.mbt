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
/// Parsed bank entry used by white-box wire-format tests. Host parsers must
/// implement the same format rather than depending on this MoonBit helper.
priv struct ParsedSoundBankEntry {
  offset : Int
  sample_count : Int
}

///|
fn sound_symbol(name : String) -> String raise {
  guard name != "" else {
    fail_cli("passport.toml: sound name must not be empty")
  }
  let chars : Array[Char] = []
  let mut segment_start = true
  for ch in name {
    if ch == '_' {
      guard !segment_start else {
        fail_cli(
          "passport.toml: sound name \"\{name}\" contains an empty segment",
        )
      }
      segment_start = true
      continue
    }
    guard ch.is_ascii_alphabetic() || ch.is_ascii_digit() else {
      fail_cli(
        "passport.toml: sound name \"\{name}\" must contain only ASCII letters, digits and underscores",
      )
    }
    if chars.length() == 0 {
      guard ch.is_ascii_alphabetic() else {
        fail_cli(
          "passport.toml: sound name \"\{name}\" must begin with an ASCII letter",
        )
      }
    }
    chars.push(if segment_start { ch.to_ascii_uppercase() } else { ch })
    segment_start = false
  }
  guard !segment_start else {
    fail_cli("passport.toml: sound name \"\{name}\" contains an empty segment")
  }
  String::from_array(chars)
}

///|
fn checked_bank_size(inputs : Array[SoundInput]) -> Int raise {
  let mut total = SOUND_BANK_HEADER_SIZE.to_int64() +
    inputs.length().to_int64() * SOUND_BANK_ENTRY_SIZE.to_int64()
  for input in inputs {
    total = total + input.pcm.length().to_int64()
    guard total <= SOUND_BANK_MAX_SIZE else {
      fail_cli("sound bank exceeds the portable v1 size limit")
    }
  }
  total.to_int()
}

///|
/// Validates sound metadata and PCM bytes, assigns declaration-order IDs and
/// emits one deterministic APSB v1 bank. Headerless PCM cannot prove sample
/// rate or channel count; callers must supply PCM16 LE mono 16000 Hz data.
pub fn compile_sounds(inputs : Array[SoundInput]) -> SoundCompilation raise {
  let names : Array[String] = []
  let symbols : Array[String] = []
  for input in inputs {
    for existing in names {
      if existing == input.entry.name {
        fail_cli("duplicate sound name \"\{input.entry.name}\"")
      }
    }
    names.push(input.entry.name)
    guard input.entry.source.has_suffix(".pcm") else {
      fail_cli(
        "sound \"\{input.entry.name}\" source must use the .pcm extension: \{input.entry.source}",
      )
    }
    guard !input.pcm.is_empty() else {
      fail_cli("sound \"\{input.entry.name}\" PCM file must not be empty")
    }
    guard input.pcm.length() % 2 == 0 else {
      fail_cli("sound \"\{input.entry.name}\" PCM byte length must be even")
    }
    let symbol = sound_symbol(input.entry.name)
    for existing in symbols {
      if existing == symbol {
        fail_cli(
          "sound names collide after MoonBit symbol generation: \"\{symbol}\"",
        )
      }
    }
    symbols.push(symbol)
  }

  let total_size = checked_bank_size(inputs)
  let payload_offset = SOUND_BANK_HEADER_SIZE +
    inputs.length() * SOUND_BANK_ENTRY_SIZE
  let sounds : Array[CompiledSound] = []
  let mut offset = payload_offset
  for id, input in inputs {
    let sample_count = input.pcm.length() / 2
    sounds.push({
      id,
      name: input.entry.name,
      symbol: symbols[id],
      source: input.entry.source,
      offset,
      sample_count,
    })
    offset += input.pcm.length()
  }

  let out = @buffer.Buffer(size_hint=total_size)
  out.write_byte(0x41)
  out.write_byte(0x50)
  out.write_byte(0x53)
  out.write_byte(0x42)
  out.write_uint16_le(SOUND_BANK_VERSION.to_uint16())
  out.write_uint16_le(SOUND_BANK_HEADER_SIZE.to_uint16())
  out.write_int_le(inputs.length())
  out.write_uint16_le(SOUND_BANK_ENTRY_SIZE.to_uint16())
  out.write_uint16_le(0)
  for sound in sounds {
    out.write_int_le(sound.offset)
    out.write_int_le(sound.sample_count)
  }
  for input in inputs {
    out.write_bytes(input.pcm)
  }
  let bank = out.to_bytes()
  guard bank.length() == total_size else {
    fail_cli("internal sound bank size mismatch")
  }
  let parsed = parse_sound_bank(bank)
  guard parsed.length() == sounds.length() else {
    fail_cli("internal sound bank entry count mismatch")
  }
  for id, entry in parsed {
    guard entry.offset == sounds[id].offset &&
      entry.sample_count == sounds[id].sample_count else {
      fail_cli("internal sound bank index mismatch")
    }
  }
  { sounds, bank, }
}

///|
fn read_u16_le(bank : Bytes, at : Int) -> Int raise {
  guard at >= 0 && at + 2 <= bank.length() else {
    fail_cli("sound bank is truncated")
  }
  bank[at].to_int() + bank[at + 1].to_int() * 0x100
}

///|
fn read_u32_le(bank : Bytes, at : Int) -> Int raise {
  guard at >= 0 && at + 4 <= bank.length() else {
    fail_cli("sound bank is truncated")
  }
  let value = bank[at].to_int64() +
    bank[at + 1].to_int64() * 0x100L +
    bank[at + 2].to_int64() * 0x1_0000L +
    bank[at + 3].to_int64() * 0x100_0000L
  guard value <= SOUND_BANK_MAX_SIZE else {
    fail_cli("sound bank contains an unsupported 32-bit value")
  }
  value.to_int()
}

///|
fn parse_sound_bank(bank : Bytes) -> Array[ParsedSoundBankEntry] raise {
  guard bank.length() >= SOUND_BANK_HEADER_SIZE else {
    fail_cli("sound bank header is truncated")
  }
  guard bank[0].to_int() == 0x41 &&
    bank[1].to_int() == 0x50 &&
    bank[2].to_int() == 0x53 &&
    bank[3].to_int() == 0x42 else {
    fail_cli("sound bank magic is invalid")
  }
  guard read_u16_le(bank, 4) == SOUND_BANK_VERSION else {
    fail_cli("sound bank version is unsupported")
  }
  guard read_u16_le(bank, 6) == SOUND_BANK_HEADER_SIZE else {
    fail_cli("sound bank header size is invalid")
  }
  let count = read_u32_le(bank, 8)
  guard read_u16_le(bank, 12) == SOUND_BANK_ENTRY_SIZE else {
    fail_cli("sound bank entry size is invalid")
  }
  guard read_u16_le(bank, 14) == 0 else {
    fail_cli("sound bank flags are unsupported")
  }
  let index_end64 = SOUND_BANK_HEADER_SIZE.to_int64() +
    count.to_int64() * SOUND_BANK_ENTRY_SIZE.to_int64()
  guard index_end64 <= bank.length().to_int64() else {
    fail_cli("sound bank index is truncated")
  }
  let entries : Array[ParsedSoundBankEntry] = []
  let mut expected_offset = index_end64.to_int()
  for id in 0..<count {
    let at = SOUND_BANK_HEADER_SIZE + id * SOUND_BANK_ENTRY_SIZE
    let offset = read_u32_le(bank, at)
    let sample_count = read_u32_le(bank, at + 4)
    guard sample_count > 0 else {
      fail_cli("sound bank entry has an empty PCM payload")
    }
    guard offset == expected_offset else {
      fail_cli("sound bank payload offsets are not contiguous")
    }
    let end64 = offset.to_int64() + sample_count.to_int64() * 2L
    guard end64 <= bank.length().to_int64() else {
      fail_cli("sound bank payload is truncated")
    }
    entries.push({ offset, sample_count, })
    expected_offset = end64.to_int()
  }
  guard expected_offset == bank.length() else {
    fail_cli("sound bank contains trailing payload bytes")
  }
  entries
}
