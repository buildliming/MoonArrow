///|
fn main {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("id", Int64, nullable=false),
    @arrow.Field::new("name", Utf8),
  ])
  let batch = try! @arrow.RecordBatch::new(schema, [
    Int64s([Some(1L), Some(9007199254740993L)]),
    Strings([Some("MoonBit 月兔"), None]),
  ])
  let bytes = try! @arrow.write_file(schema, [batch])
  let reader = try! @arrow.FileReader::new(bytes)
  let decoded = try! reader.get_batch(0)
  println(
    "Arrow IPC file: \{bytes.length()} bytes, \{reader.num_batches()} batch, \{decoded.num_rows} rows",
  )
  println("Nulls in name column: \{decoded.columns[1].null_count()}")
}
