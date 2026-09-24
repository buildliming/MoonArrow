///|
test "column summaries ignore nulls and NaNs" {
  let ints = @arrow.Column::Int32s([Some(-2), None, Some(9)])
  let summary = ints.summary()
  assert_eq(summary.length, 3)
  assert_eq(summary.null_count, 1)
  assert_true(summary.range is @arrow.ColumnRange::IntRange(-2, 9))
  let floats = @arrow.Column::Float64s([
    Some(0x7ff8000000000000L.reinterpret_as_double()),
    Some(1.5),
    Some(-2.0),
    None,
  ])
  assert_true(
    floats.summary().range is @arrow.ColumnRange::Float64Range(-2.0, 1.5),
  )
  let strings = @arrow.Column::Strings([Some("月兔"), None, Some("")])
  assert_true(
    strings.summary().range is @arrow.ColumnRange::ByteLengthRange(0, 6, 6L),
  )
}

///|
test "table summaries merge batch ranges" {
  let schema = @arrow.Schema::new([@arrow.Field::new("n", Int32)])
  let first = @arrow.RecordBatch::new(schema, [Int32s([Some(3), None])])
  let second = @arrow.RecordBatch::new(schema, [Int32s([Some(-4), Some(8)])])
  let table = @arrow.Table::new(schema, [first, second])
  let stats = table.summaries()
  assert_eq(stats[0].length, 4)
  assert_eq(stats[0].null_count, 1)
  assert_true(stats[0].range is @arrow.ColumnRange::IntRange(-4, 8))
}
