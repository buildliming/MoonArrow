///|
test "dictionary batches preserve values across base, delta and replacement" {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("category", Dictionary(0L, Utf8, false)),
  ])
  let first = @arrow.RecordBatch::new(schema, [
    Dictionaries([Some(0), Some(1), None],
      Strings([Some("red"), Some("green")]), 0L, false),
  ])
  let second = @arrow.RecordBatch::new(schema, [
    Dictionaries([Some(2), Some(0)],
      Strings([Some("red"), Some("green"), Some("blue")]), 0L, false),
  ])
  let third = @arrow.RecordBatch::new(schema, [
    Dictionaries([Some(1), Some(0)],
      Strings([Some("black"), Some("white")]), 0L, false),
  ])
  let data = @arrow.read_stream(@arrow.write_stream(schema, [first, second, third]))
  assert_eq(data.batches.length(), 3)
  assert_true(data.batches[0].columns[0] is Dictionaries(_, Strings([Some("red"), Some("green")]), _, _))
  assert_true(data.batches[1].columns[0] is Dictionaries(_, Strings([Some("red"), Some("green"), Some("blue")]), _, _))
  assert_true(data.batches[2].columns[0] is Dictionaries(_, Strings([Some("black"), Some("white")]), _, _))
  let failed = try { ignore(@arrow.write_file(schema, [first, third])); false } catch { _ => true }
  assert_true(failed)
  let file = @arrow.read_file(@arrow.write_file(schema, [first, first]))
  assert_eq(file.batches.length(), 2)
}

///|
test "dictionary rejects out-of-range indices" {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("category", Dictionary(7L, Binary, false)),
  ])
  let failed = try {
    ignore(@arrow.RecordBatch::new(schema, [Dictionaries(
      [Some(1)], Binaries([Some(b"a")]), 7L, false)]))
    false
  } catch { _ => true }
  assert_true(failed)
}
