///|
fn run_case(rows : Int, iterations : Int) -> Unit raise {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("id", Int32, nullable=false),
    @arrow.Field::new("label", Utf8),
    @arrow.Field::new("score", Float64),
  ])
  let ids = Array::makei(rows, i => Some(i))
  let labels = Array::makei(rows, i => {
    if i % 7 == 0 {
      None
    } else {
      Some("moonbit-" + (i % 97).to_string())
    }
  })
  let scores = Array::makei(rows, i => {
    if i % 11 == 0 {
      None
    } else {
      Some(i.to_double() * 0.125)
    }
  })
  let batch = @arrow.RecordBatch::new(schema, [
    Int32s(ids),
    Strings(labels),
    Float64s(scores),
  ])
  let warmup = @arrow.write_stream(schema, [batch])
  ignore(@arrow.read_stream(warmup))
  let start_encode = @env.now()
  let mut encoded = b""
  for _ in 0..<iterations {
    encoded = @arrow.write_stream(schema, [batch])
  }
  let encode_ms = @env.now() - start_encode
  let start_decode = @env.now()
  let mut decoded_rows = 0
  for _ in 0..<iterations {
    let decoded = @arrow.read_stream(encoded)
    decoded_rows += decoded.batches[0].num_rows
  }
  let decode_ms = @env.now() - start_decode
  println(
    "case," +
    rows.to_string() +
    "," +
    iterations.to_string() +
    "," +
    encoded.length().to_string() +
    "," +
    encode_ms.to_string() +
    "," +
    decode_ms.to_string() +
    "," +
    decoded_rows.to_string(),
  )
}

///|
fn main raise {
  run_case(1_000, 50)
  run_case(100_000, 8)
}
