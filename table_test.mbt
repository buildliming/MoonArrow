///|
test "table slices across batches and preserves row order" {
  let schema = @arrow.Schema::new([@arrow.Field::new("id", Int32)])
  let first = @arrow.RecordBatch::new(schema, [Int32s([Some(1), None])])
  let second = @arrow.RecordBatch::new(schema, [Int32s([Some(3), Some(4), Some(5)])])
  let table = @arrow.Table::new(schema, [first, second])
  assert_eq(table.num_rows(), 5)
  let sliced = table.slice_rows(1, 3)
  assert_eq(sliced.num_rows(), 3)
  assert_eq(sliced.num_batches(), 2)
  assert_true(sliced.get_batch(0).columns[0] is Int32s([None]))
  assert_true(sliced.get_batch(1).columns[0] is Int32s([Some(3), Some(4)]))
  let filtered = table.filter([Some(false), Some(true), None, Some(true), Some(false)])
  assert_eq(filtered.num_rows(), 2)
  let rechunked = table.rechunk(2)
  assert_eq(rechunked.num_batches(), 3)
  assert_eq(rechunked.num_rows(), 5)
  let loaded = @arrow.Table::from_file(rechunked.to_file())
  assert_eq(loaded.num_rows(), 5)
}

///|
test "table owns input arrays and rejects incompatible append" {
  let schema = @arrow.Schema::new([@arrow.Field::new("id", Int32)])
  let values : Array[Int?] = [Some(1)]
  let batch = @arrow.RecordBatch::new(schema, [Int32s(values)])
  let table = @arrow.Table::new(schema, [batch])
  values[0] = Some(9)
  assert_true(table.get_batch(0).columns[0] is Int32s([Some(1)]))
  let other_schema = @arrow.Schema::new([@arrow.Field::new("other", Int32)])
  let wrong = @arrow.RecordBatch::new(other_schema, [Int32s([Some(2)])])
  let failed = try { table.append(wrong); false } catch { _ => true }
  assert_true(failed)
  assert_eq(table.num_rows(), 1)
}
