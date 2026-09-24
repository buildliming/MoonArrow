///|
test "incremental decoder accepts every single split point" {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("id", Int64),
    @arrow.Field::new("name", Utf8),
  ])
  let batch = @arrow.RecordBatch::new(schema, [
    Int64s([Some(1L), None, Some(3L)]),
    Strings([Some("moon"), Some(""), None]),
  ])
  let bytes = @arrow.write_stream(schema, [batch])
  for split in 0..<(bytes.length() + 1) {
    let reader = @arrow.IncrementalReader::new()
    let first = reader.push(bytes.view(end=split).to_owned())
    let second = reader.push(bytes.view(start=split).to_owned())
    reader.finish()
    assert_eq(first.length() + second.length(), 1)
    assert_eq(reader.num_batches(), 1)
    assert_eq(reader.schema(), Some(schema))
  }
}

///|
test "incremental writer emits independently consumable chunks" {
  let schema = @arrow.Schema::new([@arrow.Field::new("n", Int32)])
  let first = @arrow.RecordBatch::new(schema, [Int32s([Some(1), None])])
  let second = @arrow.RecordBatch::new(schema, [Int32s([Some(3)])])
  let writer = @arrow.IncrementalWriter::new(schema)
  let header = writer.start()
  let one = writer.write_batch(first)
  let two = writer.write_batch(second)
  let eos = writer.finish()
  let reader = @arrow.IncrementalReader::new()
  assert_eq(reader.push(header).length(), 0)
  assert_eq(reader.push(one).length(), 1)
  assert_eq(reader.push(two).length(), 1)
  assert_eq(reader.push(eos).length(), 0)
  reader.finish()
  assert_eq(reader.num_batches(), 2)
  let failed = try { ignore(writer.write_batch(first)); false } catch { _ => true }
  assert_true(failed)
}

///|
test "incremental decoder rejects a truncated frame at final EOF" {
  let schema = @arrow.Schema::new([])
  let bytes = @arrow.write_stream(schema, [])
  let reader = @arrow.IncrementalReader::new()
  ignore(reader.push(bytes.view(end=bytes.length() - 1).to_owned()))
  let failed = try { reader.finish(); false } catch { _ => true }
  assert_true(failed)
  let failed = try { ignore(reader.push(b"x")); false } catch { _ => true }
  assert_true(failed)
}

///|
test "incremental file writer produces indexed multi-batch file" {
  let schema = @arrow.Schema::new([@arrow.Field::new("name", Utf8)])
  let first = @arrow.RecordBatch::new(schema, [Strings([Some("a"), None])])
  let second = @arrow.RecordBatch::new(schema, [Strings([Some("b")])])
  let writer = @arrow.FileWriter::new(schema)
  let bytes = writer.start() + writer.write_batch(first) +
    writer.write_batch(second) + writer.finish()
  let reader = @arrow.FileReader::new(bytes)
  assert_eq(reader.num_batches(), 2)
  assert_true(reader.get_batch(1).columns[0] is Strings([Some("b")]))
}
