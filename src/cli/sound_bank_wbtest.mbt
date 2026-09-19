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
