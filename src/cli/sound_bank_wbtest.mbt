///|
priv struct ParsedSoundBankEntry {
  offset : Int
  sample_count : Int
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
  let index_end = SOUND_BANK_HEADER_SIZE.to_int64() +
    count.to_int64() * SOUND_BANK_ENTRY_SIZE.to_int64()
  guard index_end <= bank.length().to_int64() else {
    fail_cli("sound bank index is truncated")
  }
  let entries : Array[ParsedSoundBankEntry] = []
  let payload_end = for id in 0..<count; expected_offset = index_end {
    let at = SOUND_BANK_HEADER_SIZE + id * SOUND_BANK_ENTRY_SIZE
    let offset = read_u32_le(bank, at)
    let sample_count = read_u32_le(bank, at + 4)
    guard sample_count > 0 else {
      fail_cli("sound bank entry has an empty PCM payload")
    }
    guard offset.to_int64() == expected_offset else {
      fail_cli("sound bank payload offsets are not contiguous")
    }
    let next = offset.to_int64() + sample_count.to_int64() * 2L
    guard next <= bank.length().to_int64() else {
      fail_cli("sound bank payload is truncated")
    }
    entries.push({ offset, sample_count, })
    continue next
  } nobreak {
    expected_offset
  }
  guard payload_end == bank.length().to_int64() else {
    fail_cli("sound bank contains trailing payload bytes")
  }
  entries
}

///|
fn compiled_test_bank() -> Bytes raise {
  compile_sounds([
    {
      entry: { name: "a", source: "assets/a.pcm", },
      pcm: Bytes::from_array([1, 0, 2, 0]),
    },
    {
      entry: { name: "b", source: "assets/b.pcm", },
      pcm: Bytes::from_array([3, 0]),
    },
  ]).bank
}

///|
test "APSB parser round-trips the real serialized index" {
  let entries = parse_sound_bank(compiled_test_bank())
  inspect(entries.length(), content="2")
  inspect(entries[0].offset, content="32")
  inspect(entries[0].sample_count, content="2")
  inspect(entries[1].offset, content="36")
  inspect(entries[1].sample_count, content="1")
  inspect(parse_sound_bank(compile_sounds([]).bank).length(), content="0")
}

///|
test "APSB parser rejects malformed headers and indexes" {
  for pair in [(0, 0), (4, 2), (6, 15), (12, 7), (14, 1)] {
    let (position, value) = pair
    let bytes = compiled_test_bank().to_array()
    bytes[position] = value.to_byte()
    try parse_sound_bank(Bytes::from_array(bytes)) catch {
      Fail(_) => ()
      _ => fail("expected CliError")
    } noraise {
      _ => fail("expected malformed bank to fail")
    }
  }
  let truncated = compiled_test_bank().to_array()
  ignore(truncated.pop())
  try parse_sound_bank(Bytes::from_array(truncated)) catch {
    Fail(_) => ()
    _ => fail("expected CliError")
  } noraise {
    _ => fail("expected truncated payload to fail")
  }
}

///|
test "APSB parser rejects non-contiguous and trailing payloads" {
  let wrong_offset = compiled_test_bank().to_array()
  wrong_offset[16] = 34
  try parse_sound_bank(Bytes::from_array(wrong_offset)) catch {
    Fail(_) => ()
    _ => fail("expected CliError")
  } noraise {
    _ => fail("expected non-contiguous offset to fail")
  }

  let empty_entry = compiled_test_bank().to_array()
  empty_entry[20] = 0
  try parse_sound_bank(Bytes::from_array(empty_entry)) catch {
    Fail(_) => ()
    _ => fail("expected CliError")
  } noraise {
    _ => fail("expected empty bank entry to fail")
  }

  let trailing = compiled_test_bank().to_array()
  trailing.push(0)
  trailing.push(0)
  try parse_sound_bank(Bytes::from_array(trailing)) catch {
    Fail(_) => ()
    _ => fail("expected CliError")
  } noraise {
    _ => fail("expected trailing payload to fail")
  }
}
