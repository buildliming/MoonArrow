///|
test "schema-only writers reject invalid nested fields" {
  let invalid = @arrow.Schema::new([
    @arrow.Field::new("xs", List, children=[]),
  ])
  let failed = try { ignore(@arrow.write_stream(invalid, [])); false } catch { _ => true }
  assert_true(failed)
  let invalid = @arrow.Schema::new([
    @arrow.Field::new("n", Int32, children=[@arrow.Field::new("child", Utf8)]),
  ])
  let failed = try { ignore(@arrow.write_file(invalid, [])); false } catch { _ => true }
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
  let failed = try { ignore(@arrow.read_stream(stream, limits~)); false } catch { _ => true }
  assert_true(failed)
  let limits = { ..@arrow.ReadLimits::default(), max_dictionary_messages: 0, }
  let failed = try { ignore(@arrow.read_stream(stream, limits~)); false } catch { _ => true }
  assert_true(failed)
}
