///|
test "IPC inspector lists schema and batch message offsets" {
  let schema = @arrow.Schema::new([@arrow.Field::new("n", Int32)])
  let batch = @arrow.RecordBatch::new(schema, [Int32s([Some(1), None])])
  let stream = @arrow.inspect_stream(@arrow.write_stream(schema, [batch]))
  assert_eq(stream.messages.length(), 2)
  assert_true(stream.has_eos)
  assert_eq(stream.messages[0].kind, @arrow.MessageKind::SchemaMessage)
  assert_eq(stream.messages[1].rows, Some(2))
  let file = @arrow.inspect_file(@arrow.write_file(schema, [batch]))
  assert_eq(file.batches.length(), 1)
  assert_eq(file.dictionaries.length(), 0)
}
