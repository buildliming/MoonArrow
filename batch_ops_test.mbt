///|
test "batch operations preserve rows, nulls and schema metadata" {
  let schema = @arrow.Schema::new(
    [@arrow.Field::new("n", Int32), @arrow.Field::new("s", Utf8)],
    metadata=[{ key: "origin", value: Some("test"), }],
  )
  let batch = @arrow.RecordBatch::new(schema, [
    Int32s([Some(1), None, Some(3)]),
    Strings([Some("a"), Some("b"), None]),
  ])
  let selected = batch.take([2, 0, 2])
  assert_true(selected.columns[0] is Int32s([Some(3), Some(1), Some(3)]))
  let filtered = batch.filter([Some(true), None, Some(false)])
  assert_eq(filtered.num_rows, 1)
  assert_true(filtered.columns[1] is Strings([Some("a")]))
  let projected = batch.project([1, 1])
  assert_eq(projected.num_rows, 3)
  assert_eq(projected.schema.fields.length(), 2)
  assert_eq(projected.schema.metadata, schema.metadata)
  let combined = batch.slice(1, 2).concat([filtered])
  assert_true(combined.columns[0] is Int32s([None, Some(3), Some(1)]))
  assert_eq(
    @arrow.read_file(@arrow.write_file(combined.schema, [combined])).batches[0].num_rows,
    3,
  )
}

///|
test "batch operations reject invalid indices and mismatched schemas" {
  let schema = @arrow.Schema::new([@arrow.Field::new("n", UInt64)])
  let batch = @arrow.RecordBatch::new(schema, [UInt64s([Some(0UL), None])])
  let failed = try {
    ignore(batch.take([2]))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  let failed = try {
    ignore(batch.slice(1, 2))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  let failed = try {
    ignore(batch.filter([Some(true)]))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  let wrong = @arrow.RecordBatch::new(
    @arrow.Schema::new([@arrow.Field::new("x", UInt64)]),
    [UInt64s([Some(1UL)])],
  )
  let failed = try {
    ignore(batch.concat([wrong]))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}
