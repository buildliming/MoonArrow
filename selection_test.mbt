///|
test "partition and global row selection preserve order" {
  let schema = @arrow.Schema::new([@arrow.Field::new("n", Int32)])
  let first = @arrow.RecordBatch::new(schema, [Int32s([Some(1), None])])
  let second = @arrow.RecordBatch::new(schema, [Int32s([Some(3), Some(4)])])
  let table = @arrow.Table::new(schema, [first, second])
  let picked = table.take_rows([3, 0, 3])
  assert_eq(picked.num_rows(), 3)
  assert_true(picked.get_batch(0).columns[0] is Int32s([Some(4)]))
  let (yes, no) = table.partition_where(@arrow.Predicate::IsNull(0))
  assert_eq(yes.num_rows(), 1)
  assert_eq(no.num_rows(), 3)
  assert_eq(table.head(2).num_rows(), 2)
  assert_eq(table.tail(2).num_rows(), 2)
}

///|
test "table take_rows groups consecutive source rows across empty batches" {
  let schema = @arrow.Schema::new([@arrow.Field::new("n", Int32)])
  let values : Array[Int?] = [Some(1), None, Some(3)]
  let empty = @arrow.RecordBatch::new(schema, [Int32s([])])
  let first = @arrow.RecordBatch::new(schema, [Int32s(values)])
  let second = @arrow.RecordBatch::new(schema, [Int32s([Some(4), Some(5)])])
  let table = @arrow.Table::new(schema, [empty, first, empty, second, empty])
  let picked = table.take_rows([0, 2, 1, 4, 3, 0, 0])
  values[0] = Some(99)
  assert_eq(picked.num_rows(), 7)
  assert_eq(picked.num_batches(), 3)
  assert_true(
    picked.get_batch(0).columns[0] is Int32s([Some(1), Some(3), None]),
  )
  assert_true(picked.get_batch(1).columns[0] is Int32s([Some(5), Some(4)]))
  assert_true(picked.get_batch(2).columns[0] is Int32s([Some(1), Some(1)]))
  assert_eq(table.take_rows([]).num_batches(), 0)
  for invalid in [-1, 5] {
    assert_true(
      try {
        ignore(table.take_rows([0, invalid]))
        false
      } catch {
        @arrow.ArrowError::Invalid(_) => true
        _ => false
      },
    )
  }
}

///|
test "table take_rows keeps per-batch dictionary values when sources alternate" {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("category", Dictionary(0L, Utf8, false)),
  ])
  let first = @arrow.RecordBatch::new(schema, [
    Dictionaries(
      [Some(0), Some(1)],
      Strings([Some("red"), Some("green")]),
      0L,
      false,
    ),
  ])
  let second = @arrow.RecordBatch::new(schema, [
    Dictionaries(
      [Some(1), Some(0)],
      Strings([Some("blue"), Some("white")]),
      0L,
      false,
    ),
  ])
  let table = @arrow.Table::new(schema, [first, second])
  let picked = table.take_rows([0, 1, 3, 2, 1, 0, 3])
  assert_eq(picked.num_batches(), 4)
  assert_true(picked.get_row(0)[0] is Some(Utf8Value("red")))
  assert_true(picked.get_row(1)[0] is Some(Utf8Value("green")))
  assert_true(picked.get_row(2)[0] is Some(Utf8Value("blue")))
  assert_true(picked.get_row(3)[0] is Some(Utf8Value("white")))
  assert_true(picked.get_row(4)[0] is Some(Utf8Value("green")))
  assert_true(picked.get_row(5)[0] is Some(Utf8Value("red")))
  assert_true(picked.get_row(6)[0] is Some(Utf8Value("blue")))
  let decoded = @arrow.Table::from_stream(picked.to_stream())
  assert_true(decoded.get_row(6)[0] is Some(Utf8Value("blue")))
}
