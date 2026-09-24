///|
test "row builder is atomic and finish returns an owned snapshot" {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("id", UInt64, nullable=false),
    @arrow.Field::new("name", Utf8),
    @arrow.Field::new("day", Date32),
  ])
  let builder = @arrow.BatchBuilder::new(schema)
  builder.append_row([
    Some(UInt64Value(18446744073709551615UL)),
    Some(Utf8Value("first")),
    Some(Date32Value(1)),
  ])
  let first = builder.finish()
  let failed = try {
    builder.append_row([Some(UInt64Value(2UL)), Some(Int32Value(7)), None])
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_eq(builder.num_rows(), 1)
  builder.append_row([Some(UInt64Value(2UL)), None, Some(Date32Value(-1))])
  assert_eq(first.num_rows, 1)
  assert_true(first.columns[1] is Strings([Some("first")]))
  let second = builder.finish()
  assert_eq(second.num_rows, 2)
  assert_true(second.columns[1] is Strings([Some("first"), None]))
  let roundtrip = @arrow.read_stream(
    @arrow.write_stream(second.schema, [second]),
  )
  assert_eq(roundtrip.batches[0].num_rows, 2)
}

///|
test "row builder constructs nested arrays and null parents" {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("items", List, children=[
      @arrow.Field::new("item", Int32, nullable=false),
    ]),
    @arrow.Field::new("pair", Struct, children=[
      @arrow.Field::new("n", Int16, nullable=false),
      @arrow.Field::new("s", Utf8),
    ]),
  ])
  let builder = @arrow.BatchBuilder::new(schema)
  builder.append_row([
    Some(ListValue([Some(Int32Value(1)), Some(Int32Value(2))])),
    Some(StructValue([Some(Int16Value(7)), Some(Utf8Value("x"))])),
  ])
  builder.append_row([None, None])
  let batch = builder.finish()
  assert_true(batch.columns[0] is Lists([0, 2, 2], [true, false], _))
  assert_eq(batch.columns[1].null_count(), 1)
  let decoded = @arrow.read_stream(@arrow.write_stream(schema, [batch]))
  assert_eq(decoded.batches[0].num_rows, 2)
  let failed = try {
    builder.append_row([Some(ListValue([None])), None])
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_eq(builder.num_rows(), 2)
}
