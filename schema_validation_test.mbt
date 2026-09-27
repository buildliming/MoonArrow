///|
test "schema-only writers reject invalid nested fields" {
  let invalid = @arrow.Schema::new([@arrow.Field::new("xs", List, children=[])])
  let failed = try {
    ignore(@arrow.write_stream(invalid, []))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  let invalid = @arrow.Schema::new([
    @arrow.Field::new("n", Int32, children=[@arrow.Field::new("child", Utf8)]),
  ])
  let failed = try {
    ignore(@arrow.write_file(invalid, []))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "dictionary reader budgets stop state growth" {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("category", Dictionary(0L, Utf8, false)),
  ])
  let batch = @arrow.RecordBatch::new(schema, [
    Dictionaries([Some(0)], Strings([Some("a"), Some("b")]), 0L, false),
  ])
  let stream = @arrow.write_stream(schema, [batch])
  let limits = { ..@arrow.ReadLimits::default(), max_dictionary_values: 1, }
  let failed = try {
    ignore(@arrow.read_stream(stream, limits~))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  let limits = { ..@arrow.ReadLimits::default(), max_dictionary_messages: 0, }
  let failed = try {
    ignore(@arrow.read_stream(stream, limits~))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "stream reader batch schema does not mutate reader state" {
  let schema = @arrow.Schema::new([@arrow.Field::new("value", Int32)])
  let batch = @arrow.RecordBatch::new(schema, [Int32s([Some(7)])])
  let reader = @arrow.StreamReader::new(
    @arrow.write_stream(schema, [batch, batch]),
  )
  guard reader.next() is Some(first) else { fail("missing first batch") }
  first.schema.fields[0] = @arrow.Field::new("changed", Utf8)
  assert_eq(reader.schema.fields[0].name, "value")
  guard reader.next() is Some(second) else { fail("missing second batch") }
  assert_eq(second.schema.fields[0].name, "value")
  assert_true(second.columns[0] is Int32s([Some(7)]))
}

///|
test "file reader batch schema does not mutate reader state" {
  let schema = @arrow.Schema::new([@arrow.Field::new("value", Int32)])
  let batch = @arrow.RecordBatch::new(schema, [Int32s([Some(7)])])
  let reader = @arrow.FileReader::new(@arrow.write_file(schema, [batch, batch]))
  let first = reader.get_batch(0)
  first.schema.fields[0] = @arrow.Field::new("changed", Utf8)
  assert_eq(reader.schema.fields[0].name, "value")
  let second = reader.get_batch(1)
  assert_eq(second.schema.fields[0].name, "value")
  assert_true(second.columns[0] is Int32s([Some(7)]))
}
