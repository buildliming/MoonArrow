///|
fn add_buffer(
  body : Array[Byte],
  buffers : Array[(Int, Int)],
  bytes : Bytes,
) -> Unit {
  align_bytes(body, 8)
  buffers.push((body.length(), bytes.length()))
  append_bytes(body, bytes)
}

///|
fn encode_body(batch : RecordBatch) -> BodyLayout raise ArrowError {
  batch.validate()
  let body : Array[Byte] = []
  let nodes = []
  let buffers = []
  for column in batch.columns {
    let n = batch.num_rows
    let nulls = column.null_count()
    nodes.push((n, nulls))
    if column is Nulls(_) {
      continue
    }
    let bitmap : Array[Byte] = []
    if nulls > 0 {
      ignore(reserve(bitmap, n / 8 + (if n % 8 != 0 { 1 } else { 0 })))
      for i in 0..<n {
        if column.valid_at(i) {
          bitmap[i / 8] = (bitmap[i / 8].to_int() | (1 << (i % 8))).to_byte()
        }
      }
    }
    add_buffer(body, buffers, Bytes::from_array(bitmap))
    let values : Array[Byte] = []
    match column {
      Nulls(_) => ()
      Booleans(a) => {
        ignore(reserve(values, n / 8 + (if n % 8 != 0 { 1 } else { 0 })))
        for i in 0..<n {
          if a[i] == Some(true) {
            values[i / 8] = (values[i / 8].to_int() | (1 << (i % 8))).to_byte()
          }
        }
      }
      Int32s(a) =>
        for value in a {
          put_i32(values, reserve(values, 4), value.unwrap_or(0))
        }
      Int64s(a) =>
        for value in a {
          put_i64(values, reserve(values, 8), value.unwrap_or(0L))
        }
      Float64s(a) =>
        for value in a {
          put_i64(
            values,
            reserve(values, 8),
            value.unwrap_or(0.0).reinterpret_as_int64(),
          )
        }
      Strings(_) | Binaries(_) => {
        let offsets : Array[Byte] = []
        put_i32(offsets, reserve(offsets, 4), 0)
        for i in 0..<n {
          let bytes = match column {
            Strings(a) =>
              match a[i] {
                Some(s) => @utf8.encode(s)
                None => b""
              }
            Binaries(a) => a[i].unwrap_or(b"")
            _ => b""
          }
          if bytes.length() > 0x7fffffff - values.length() {
            raise LimitExceeded("32-bit binary offsets")
          }
          append_bytes(values, bytes)
          put_i32(offsets, reserve(offsets, 4), values.length())
        }
        add_buffer(body, buffers, Bytes::from_array(offsets))
      }
    }
    add_buffer(body, buffers, Bytes::from_array(values))
  }
  align_bytes(body, 8)
  { body: Bytes::from_array(body), nodes, buffers, }
}

///|
fn body_buffer(frame : Frame, base : Int, i : Int) -> Bytes raise ArrowError {
  let offset = bounded_i64(
    read_i64(frame.metadata, base + i * 16),
    frame.body.length(),
    "buffer offset",
  )
  let size = bounded_i64(
    read_i64(frame.metadata, base + i * 16 + 8),
    frame.body.length(),
    "buffer size",
  )
  slice_bytes(frame.body, offset, size)
}

///|
fn decode_body(
  frame : Frame,
  schema : Schema,
  limits : ReadLimits,
) -> RecordBatch raise ArrowError {
  if frame.kind != 3 {
    raise Unsupported("expected RecordBatch message")
  }
  let metadata = frame.metadata
  let table = frame.header
  if field_ref(metadata, table, 3) is Some(_) {
    raise Unsupported("compressed IPC body")
  }
  let (_, variadic) = vector_info(metadata, table, 4, 8, limits.max_fields)
  if variadic != 0 {
    raise Unsupported("variadic buffers")
  }
  let rows = bounded_i64(
    field_long(metadata, table, 0),
    limits.max_rows_per_batch,
    "rows per batch",
  )
  let count = schema.fields.length()
  if count > 0 && rows > limits.max_values_per_batch / count {
    raise LimitExceeded("values per batch")
  }
  let (nodes, node_count) = vector_info(
    metadata,
    table,
    1,
    16,
    limits.max_fields,
  )
  if node_count != count {
    raise Invalid("field node count differs from schema")
  }
  let mut expected_buffers = 0
  for field in schema.fields {
    expected_buffers += match field.data_type {
      Null => 0
      Utf8 | Binary => 3
      _ => 2
    }
  }
  let (buffers, buffer_count) = vector_info(
    metadata, table, 2, 16, expected_buffers,
  )
  if buffer_count != expected_buffers {
    raise Invalid("buffer count differs from schema")
  }
  // Bound copied buffers even if malformed metadata aliases the same body range
  // many times. This is a byte budget, not an exact process-memory limit.
  let mut remaining_bytes = limits.max_body_bytes
  for i in 0..<buffer_count {
    let size = bounded_i64(
      read_i64(metadata, buffers + i * 16 + 8),
      remaining_bytes,
      "total buffer bytes",
    )
    remaining_bytes -= size
  }
  let mut cursor = 0
  let columns = []
  for i in 0..<count {
    let length = bounded_i64(
      read_i64(metadata, nodes + i * 16),
      limits.max_rows_per_batch,
      "column length",
    )
    let nulls = bounded_i64(
      read_i64(metadata, nodes + i * 16 + 8),
      rows,
      "null count",
    )
    if length != rows {
      raise Invalid("field node length differs from batch")
    }
    let field = schema.fields[i]
    if field.data_type == Null {
      if nulls != rows {
        raise Invalid("Null column null count differs from length")
      }
      columns.push(Column::Nulls(rows))
      continue
    }
    let validity = body_buffer(frame, buffers, cursor)
    cursor += 1
    let bitmap_size = rows / 8 + (if rows % 8 != 0 { 1 } else { 0 })
    if !validity.is_empty() && validity.length() < bitmap_size {
      raise Invalid("short validity bitmap")
    }
    if nulls > 0 && validity.length() < bitmap_size {
      raise Invalid("missing validity bitmap")
    }
    let valid : Array[Bool] = []
    let mut actual_nulls = 0
    for j in 0..<rows {
      let bit = validity.is_empty() ||
        (validity[j / 8].to_int() & (1 << (j % 8))) != 0
      valid.push(bit)
      if !bit {
        actual_nulls += 1
      }
    }
    if actual_nulls != nulls {
      raise Invalid("null count does not match validity bitmap")
    }
    let values = body_buffer(frame, buffers, cursor)
    cursor += 1
    let column = match field.data_type {
      Null => Column::Nulls(rows)
      Boolean => {
        if values.length() < bitmap_size {
          raise Invalid("short boolean bitmap")
        }
        Booleans(
          Array::makei(rows, j => {
            if valid[j] {
              Some((values[j / 8].to_int() & (1 << (j % 8))) != 0)
            } else {
              None
            }
          }),
        )
      }
      Int32 => {
        if rows > values.length() / 4 {
          raise Invalid("short Int32 buffer")
        }
        let result = []
        for j in 0..<rows {
          result.push(
            if valid[j] {
              Some(read_i32(values, j * 4))
            } else {
              None
            },
          )
        }
        Int32s(result)
      }
      Int64 => {
        if rows > values.length() / 8 {
          raise Invalid("short Int64 buffer")
        }
        let result = []
        for j in 0..<rows {
          result.push(
            if valid[j] {
              Some(read_i64(values, j * 8))
            } else {
              None
            },
          )
        }
        Int64s(result)
      }
      Float64 => {
        if rows > values.length() / 8 {
          raise Invalid("short Float64 buffer")
        }
        let result = []
        for j in 0..<rows {
          result.push(
            if valid[j] {
              Some(read_i64(values, j * 8).reinterpret_as_double())
            } else {
              None
            },
          )
        }
        Float64s(result)
      }
      Utf8 | Binary => {
        let bytes = body_buffer(frame, buffers, cursor)
        cursor += 1
        if rows >= values.length() / 4 {
          raise Invalid("short offsets buffer")
        }
        let strings = []
        let binaries = []
        let mut start = read_i32(values, 0)
        if start < 0 || start > bytes.length() {
          raise Invalid("invalid first binary offset")
        }
        for j in 0..<rows {
          let end = read_i32(values, (j + 1) * 4)
          if end < start || end > bytes.length() {
            raise Invalid("non-monotonic or out-of-range offset")
          }
          if field.data_type == Utf8 {
            strings.push(
              if valid[j] {
                Some(decode_utf8(bytes, start, end - start))
              } else {
                None
              },
            )
          } else {
            binaries.push(
              if valid[j] {
                Some(slice_bytes(bytes, start, end - start))
              } else {
                None
              },
            )
          }
          start = end
        }
        if field.data_type == Utf8 {
          Strings(strings)
        } else {
          Binaries(binaries)
        }
      }
    }
    columns.push(column)
  }
  RecordBatch::new(schema, columns, num_rows=rows)
}
