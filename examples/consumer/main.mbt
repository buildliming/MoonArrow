///|
/// Independent module exercising only MoonArrow's public package API.
fn main raise {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("id", Int32, nullable=false),
    @arrow.Field::new("city", Utf8),
  ])
  let builder = @arrow.BatchBuilder::new(schema)
  builder.append_row([Some(Int32Value(1)), Some(Utf8Value("上海"))])
  builder.append_row([Some(Int32Value(2)), None])
  builder.append_row([Some(Int32Value(3)), Some(Utf8Value("北京"))])
  let table = @arrow.Table::new(schema, [builder.finish()])
  let selected = table.filter_where(IsNotNull(1)).select(["city", "id"])
  let restored = @arrow.Table::from_file(selected.to_file())
  assert_eq(restored.num_rows(), 2)
  assert_eq(restored.schema.fields[0].name, "city")
  assert_true(restored.get_row(1)[0] is Some(Utf8Value("北京")))
  println("consumer: 2 rows round-tripped")
}
