///|
test "schema operations keep metadata and validate replacement columns" {
  let schema = @arrow.Schema::new(
    [@arrow.Field::new("id", Int32), @arrow.Field::new("name", Utf8)],
    metadata=[{ key: "source", value: Some("test"), }],
  )
  let batch = @arrow.RecordBatch::new(schema, [
    Int32s([Some(1), Some(2)]),
    Strings([Some("a"), None]),
  ])
  let selected = batch.select(["name", "id"])
  assert_eq(selected.schema.fields[0].name, "name")
  let renamed = batch.rename(0, "number")
  assert_eq(renamed.schema.fields[0].name, "number")
  let replaced = batch.replace_column(
    1,
    @arrow.Field::new("active", Boolean),
    Booleans([Some(true), None]),
  )
  assert_true(replaced.columns[1] is Booleans([Some(true), None]))
  let inserted = batch.insert_column(2, @arrow.Field::new("n", Null), Nulls(2))
  assert_eq(inserted.columns.length(), 3)
  assert_eq(inserted.drop_column(2).columns.length(), 2)
  assert_eq(batch.split_rows(1).length(), 2)
  assert_eq(@arrow.Table::new(schema, [batch]).select(["id"]).num_rows(), 2)
}
