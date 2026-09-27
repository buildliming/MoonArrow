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

///|
test "table scalar access crosses empty batches and keeps owned nullable rows" {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("id", Int32),
    @arrow.Field::new("name", Utf8),
  ])
  let ids : Array[Int?] = [Some(1), None]
  let names : Array[String?] = [None, Some("moon")]
  let empty = @arrow.RecordBatch::new(schema, [Int32s([]), Strings([])])
  let first = @arrow.RecordBatch::new(schema, [Int32s(ids), Strings(names)])
  let last = @arrow.RecordBatch::new(schema, [
    Int32s([Some(3)]),
    Strings([Some("arrow")]),
  ])
  let table = @arrow.Table::new(schema, [empty, first, empty, last])
  ids[0] = Some(99)
  names[1] = Some("changed")
  assert_true(table.get_row(0) is [Some(Int32Value(1)), None])
  assert_true(table.get_row(1) is [None, Some(Utf8Value("moon"))])
  assert_true(
    table.get_row(2) is [Some(Int32Value(3)), Some(Utf8Value("arrow"))],
  )
  assert_true(
    try {
      ignore(table.get_row(-1))
      false
    } catch {
      @arrow.ArrowError::Invalid(_) => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(table.get_row(3))
      false
    } catch {
      @arrow.ArrowError::Invalid(_) => true
      _ => false
    },
  )
}
