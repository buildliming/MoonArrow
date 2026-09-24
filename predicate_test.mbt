///|
test "typed predicates filter nulls and values with stable float bits" {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("id", Int32),
    @arrow.Field::new("score", Float64),
  ])
  let batch = @arrow.RecordBatch::new(schema, [
    Int32s([Some(1), None, Some(3), Some(4)]),
    Float64s([Some(0.0), None, Some(-0.0), Some(1.0)]),
  ])
  let selected = batch.filter_where(
    @arrow.Predicate::Or(Eq(1, Float64Value(-0.0)), IsNull(0)),
  )
  assert_true(selected.columns[0] is Int32s([None, Some(3)]))
  let table = @arrow.Table::new(schema, [batch])
  let selected = table.filter_where(
    @arrow.Predicate::And(IsNotNull(0), Ne(0, Int32Value(4))),
  )
  assert_eq(selected.num_rows(), 2)
  let failed = try {
    ignore(batch.filter_where(Eq(0, Utf8Value("wrong"))))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}
