///|
test "nested List and Struct roundtrip and batch operations" {
  let item = @arrow.Field::new("item", Int32)
  let list_field = @arrow.Field::new("numbers", List, children=[item])
  let struct_field = @arrow.Field::new("record", Struct, children=[
    @arrow.Field::new("code", Int16),
    @arrow.Field::new("label", Utf8),
  ])
  let schema = @arrow.Schema::new([list_field, struct_field])
  let batch = @arrow.RecordBatch::new(schema, [
    Lists([0, 2, 2, 2, 3], [true, false, true, true],
      Int32s([Some(1), None, Some(3)])),
    Structs([true, false, true, true], [
      Int16s([Some(1), None, Some(2), Some(-1)]),
      Strings([Some("a"), None, None, Some("z")]),
    ]),
  ])
  let decoded = @arrow.read_file(@arrow.write_file(schema, [batch])).batches[0]
  assert_true(decoded.columns[0] is Lists([0, 2, 2, 2, 3],
    [true, false, true, true], _))
  assert_eq(decoded.columns[1].null_count(), 1)
  let selected = decoded.take([3, 0, 1])
  let projected = selected.project([1])
  assert_eq(projected.num_rows, 3)
  let combined = projected.concat([projected])
  assert_eq(combined.num_rows, 6)
  let stream = @arrow.read_stream(@arrow.write_stream(combined.schema, [combined]))
  assert_eq(stream.batches[0].num_rows, 6)
}

///|
test "invalid nested offsets and recursion budget are rejected" {
  let field = @arrow.Field::new("xs", List,
    children=[@arrow.Field::new("item", Int32)])
  let schema = @arrow.Schema::new([field])
  let failed = try {
    ignore(@arrow.RecordBatch::new(schema, [Lists([0, 2], [true], Int32s([Some(1)]) )]))
    false
  } catch { _ => true }
  assert_true(failed)
  let batch = @arrow.RecordBatch::new(schema, [Lists([0, 1], [true], Int32s([Some(1)]))])
  let bytes = @arrow.write_stream(schema, [batch])
  let limits = { ..@arrow.ReadLimits::default(), max_depth: 0, }
  let failed = try { ignore(@arrow.read_stream(bytes, limits~)); false } catch { _ => true }
  assert_true(failed)
}
