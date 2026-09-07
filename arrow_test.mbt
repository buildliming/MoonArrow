///|
fn basic_batch() -> @arrow.RecordBatch raise {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("a", Int32),
    @arrow.Field::new("b", Utf8),
  ])
  @arrow.RecordBatch::new(schema, [
    Int32s([Some(1), None, Some(-7)]),
    Strings([Some("月兔🐇"), Some(""), None]),
  ])
}

///|
test "stream and file preserve nullable columns and batch boundaries" {
  let batch = basic_batch()
  let stream = @arrow.read_stream(
    @arrow.write_stream(batch.schema, [batch, batch]),
  )
  assert_eq(stream.batches.length(), 2)
  assert_eq(stream.schema, batch.schema)
  assert_true(stream.batches[0].columns[0] is Int32s([Some(1), None, Some(-7)]))
  assert_true(
    stream.batches[1].columns[1]
    is Strings([Some("月兔🐇"), Some(""), None]),
  )
  let file = @arrow.FileReader::new(
    @arrow.write_file(batch.schema, [batch, batch]),
  )
  assert_eq(file.num_batches(), 2)
  assert_true(file.get_batch(1).columns[0] is Int32s([Some(1), None, Some(-7)]))
  assert_true(
    file.get_batch(0).columns[1]
    is Strings([Some("月兔🐇"), Some(""), None]),
  )
}

///|
test "empty schema and zero-column nonempty batches" {
  let schema = @arrow.Schema::new([])
  let empty_stream = @arrow.read_stream(@arrow.write_stream(schema, []))
  assert_eq(empty_stream.batches.length(), 0)
  let batch = @arrow.RecordBatch::new(schema, [], num_rows=7)
  let file = @arrow.read_file(@arrow.write_file(schema, [batch]))
  assert_eq(file.batches[0].num_rows, 7)
  assert_eq(file.batches[0].columns.length(), 0)
}

///|
test "schema-only IPC files are readable" {
  let schema = basic_batch().schema
  let file = @arrow.FileReader::new(@arrow.write_file(schema, []))
  assert_eq(file.num_batches(), 0)
  assert_eq(file.schema, schema)
}

///|
test "reader reaches EOS repeatedly and accepts clean EOF" {
  let batch = basic_batch()
  let bytes = @arrow.write_stream(batch.schema, [batch])
  let reader = @arrow.StreamReader::new(bytes)
  assert_true(reader.next() is Some(_))
  assert_true(reader.next() is None)
  assert_true(reader.next() is None)
  let no_eos = bytes.view(end=bytes.length() - 8).to_owned()
  assert_eq(@arrow.read_stream(no_eos).batches.length(), 1)
}

///|
test "invalid batches are rejected and mutable input is revalidated" {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("a", Int32, nullable=false),
  ])
  let a : Array[Int?] = [Some(1)]
  let batch = @arrow.RecordBatch::new(schema, [Int32s(a)])
  a[0] = None
  let result = try {
    ignore(@arrow.write_stream(schema, [batch]))
    false
  } catch {
    _ => true
  }
  assert_true(result)
  let wrong_type = try {
    ignore(@arrow.RecordBatch::new(schema, [Strings([Some("x")])]))
    false
  } catch {
    _ => true
  }
  assert_true(wrong_type)
  let negative = try {
    ignore(@arrow.RecordBatch::new(@arrow.Schema::new([]), [], num_rows=-1))
    false
  } catch {
    _ => true
  }
  assert_true(negative)
}

///|
test "schema and field metadata preserve order duplicates missing values and BOM" {
  let metadata : Array[@arrow.KeyValue] = [
    { key: "same", value: Some("first"), },
    { key: "same", value: None, },
    { key: "\u{FEFF}key", value: Some("月兔\u{0000}"), },
  ]
  let schema = @arrow.Schema::new(
    [@arrow.Field::new("\u{FEFF}field", Utf8, metadata~)],
    metadata~,
  )
  assert_eq(@arrow.read_stream(@arrow.write_stream(schema, [])).schema, schema)
  assert_eq(@arrow.read_file(@arrow.write_file(schema, [])).schema, schema)
}

///|
test "floating point bit patterns and Int64 extremes survive roundtrip" {
  let bits = [
    0L, -9223372036854775808L, 0x7ff0000000000000L, 0xfff0000000000000L, 0x7ff8000000000042L,
    1L,
  ]
  let schema = @arrow.Schema::new([
    @arrow.Field::new("f", Float64),
    @arrow.Field::new("i", Int64),
  ])
  let batch = @arrow.RecordBatch::new(schema, [
    Float64s(bits.map(b => Some(b.reinterpret_as_double()))),
    Int64s(bits.map(b => Some(b))),
  ])
  let decoded = @arrow.read_file(@arrow.write_file(schema, [batch])).batches[0]
  guard decoded.columns[0] is Float64s(values) else { fail("wrong type") }
  for i in 0..<bits.length() {
    assert_eq(values[i].unwrap().reinterpret_as_int64(), bits[i])
  }
  guard decoded.columns[1] is Int64s(values) else { fail("wrong type") }
  for i in 0..<bits.length() {
    assert_eq(values[i], Some(bits[i]))
  }
}

///|
test "reader limits and bad file indices fail explicitly" {
  let batch = basic_batch()
  let bytes = @arrow.write_stream(batch.schema, [batch])
  let limits = { ..@arrow.ReadLimits::default(), max_rows_per_batch: 2, }
  let result = try {
    ignore(@arrow.read_stream(bytes, limits~))
    false
  } catch {
    _ => true
  }
  assert_true(result)
  let file = @arrow.FileReader::new(@arrow.write_file(batch.schema, [batch]))
  let result = try {
    ignore(file.get_batch(1))
    false
  } catch {
    _ => true
  }
  assert_true(result)
}

///|
test "truncation of an IPC file never succeeds" {
  let batch = basic_batch()
  let bytes = @arrow.write_file(batch.schema, [batch])
  for end in 0..<bytes.length() {
    let result = try {
      ignore(@arrow.read_file(bytes.view(end~).to_owned()))
      false
    } catch {
      _ => true
    }
    assert_true(result)
  }
}

///|
test "bytes following EOS are rejected" {
  let bytes = @arrow.write_stream(@arrow.Schema::new([]), []) + b"trailing"
  let result = try {
    ignore(@arrow.read_stream(bytes))
    false
  } catch {
    _ => true
  }
  assert_true(result)
}
