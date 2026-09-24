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
