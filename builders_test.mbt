///|
test "row builder is atomic and finish returns an owned snapshot" {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("id", UInt64, nullable=false),
    @arrow.Field::new("name", Utf8),
    @arrow.Field::new("day", Date32),
  ])
  let builder = @arrow.BatchBuilder::new(schema)
  builder.append_row([Some(UInt64Value(18446744073709551615UL)),
    Some(Utf8Value("first")), Some(Date32Value(1))])
  let first = builder.finish()
  let failed = try {
    builder.append_row([Some(UInt64Value(2UL)), Some(Int32Value(7)), None])
    false
  } catch { _ => true }
  assert_true(failed)
  assert_eq(builder.num_rows(), 1)
  builder.append_row([Some(UInt64Value(2UL)), None, Some(Date32Value(-1))])
  assert_eq(first.num_rows, 1)
  assert_true(first.columns[1] is Strings([Some("first")]))
  let second = builder.finish()
  assert_eq(second.num_rows, 2)
  assert_true(second.columns[1] is Strings([Some("first"), None]))
  let roundtrip = @arrow.read_stream(@arrow.write_stream(second.schema, [second]))
  assert_eq(roundtrip.batches[0].num_rows, 2)
}
