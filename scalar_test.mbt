///|
test "scalar access resolves nested maps and builder can append batches" {
  let entries = @arrow.Field::new("entries", Struct, nullable=false, children=[
    @arrow.Field::new("key", Utf8, nullable=false),
    @arrow.Field::new("value", Int32),
  ])
  let schema = @arrow.Schema::new([
    @arrow.Field::new("attrs", Map(false), children=[entries]),
  ])
  let builder = @arrow.BatchBuilder::new(schema)
  builder.append_row([Some(MapValue([(Utf8Value("a"), Some(Int32Value(1)))]))])
  builder.append_row([None])
  let batch = builder.finish()
  assert_true(batch.get_row(0)[0] is Some(MapValue(_)))
  assert_true(batch.get_row(1)[0] is None)
  let output = @arrow.BatchBuilder::new(schema)
  output.append_batch(batch)
  assert_eq(output.num_rows(), 2)
  let decoded = @arrow.read_stream(
    @arrow.write_stream(schema, [output.finish()]),
  )
  assert_true(decoded.batches[0].get_row(0)[0] is Some(MapValue(_)))
}
