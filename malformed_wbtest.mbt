///|
fn rejects_stream(bytes : Bytes) -> Bool {
  try {
    ignore(read_stream(bytes))
    false
  } catch {
    _ => true
  }
}

///|
fn bytes_array(bytes : Bytes) -> Array[Byte] {
  Array::makei(bytes.length(), i => bytes[i])
}

///|
fn framed_batch(schema : Schema, rows : Int, layout : BodyLayout) -> Bytes {
  let out : Array[Byte] = []
  write_frame(out, schema_message(schema), b"")
  write_frame(out, batch_message(rows, layout), layout.body)
  write_eos(out)
  Bytes::from_array(out)
}

///|
test "malformed record batch lengths buffers null counts and offsets" {
  let schema = Schema::new([Field::new("s", Utf8)])
  let batch = RecordBatch::new(schema, [Strings([Some("ok"), None])])
  let layout = encode_body(batch)
  assert_true(rejects_stream(framed_batch(schema, 3, layout)))
  assert_true(
    rejects_stream(framed_batch(schema, 2, { ..layout, nodes: [(2, 0)], })),
  )
  assert_true(rejects_stream(framed_batch(schema, 2, { ..layout, nodes: [], })))
  assert_true(
    rejects_stream(framed_batch(schema, 2, { ..layout, buffers: [], })),
  )
  let bad_buffers = layout.buffers.copy()
  bad_buffers[1] = (0, 4)
  assert_true(
    rejects_stream(framed_batch(schema, 2, { ..layout, buffers: bad_buffers, })),
  )
  bad_buffers[1] = (layout.body.length(), 4)
  assert_true(
    rejects_stream(framed_batch(schema, 2, { ..layout, buffers: bad_buffers, })),
  )
  let body = bytes_array(layout.body)
  let (offsets, _) = layout.buffers[1]
  put_i32(body, offsets + 8, 1)
  assert_true(
    rejects_stream(
      framed_batch(schema, 2, { ..layout, body: Bytes::from_array(body), }),
    ),
  )
}

///|
test "invalid UTF8 and missing validity bitmap are rejected" {
  let schema = Schema::new([Field::new("s", Utf8)])
  let layout = encode_body(
    RecordBatch::new(schema, [Strings([Some("x"), None])]),
  )
  let body = bytes_array(layout.body)
  let (text_start, _) = layout.buffers[2]
  body[text_start] = b'\xff'
  assert_true(
    rejects_stream(
      framed_batch(schema, 2, { ..layout, body: Bytes::from_array(body), }),
    ),
  )
  let buffers = layout.buffers.copy()
  buffers[0] = (0, 0)
  assert_true(rejects_stream(framed_batch(schema, 2, { ..layout, buffers, })))
}

///|
test "oversized and negative frame prefixes fail without allocation" {
  assert_true(rejects_stream(b"\xff\xff\xff\xff\xff\xff\xff\x7f"))
  assert_true(rejects_stream(b"\xff\xff\xff\xff\xfe\xff\xff\xff"))
  assert_true(rejects_stream(b"\xff\xff\xff\xff"))
  let bytes = bytes_array(write_stream(Schema::new([]), []))
  put_i32(bytes, 8, 0x7fffffff)
  assert_true(rejects_stream(Bytes::from_array(bytes)))
}

///|
test "batch value limits stop wide input before column allocation" {
  let schema = Schema::new([Field::new("a", Int32), Field::new("b", Int32)])
  let batch = RecordBatch::new(schema, [
    Int32s([Some(1), None]),
    Int32s([None, Some(2)]),
  ])
  let data = write_stream(schema, [batch])
  let limits = { ..ReadLimits::default(), max_values_per_batch: 3, }
  let limited = try {
    ignore(read_stream(data, limits~))
    false
  } catch {
    LimitExceeded(_) => true
    _ => false
  }
  assert_true(limited)
}

///|
test "reader becomes terminal after a malformed batch" {
  let schema = Schema::new([Field::new("a", Int32)])
  let layout = encode_body(RecordBatch::new(schema, [Int32s([Some(1)])]))
  let reader = StreamReader::new(framed_batch(schema, 2, layout))
  let failed = try {
    ignore(reader.next())
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_true(reader.next() is None)
}

///|
test "deterministic malformed byte corpus does not panic" {
  let limits = {
    ..ReadLimits::default(),
    max_rows_per_batch: 64,
    max_fields: 8,
    max_batches: 4,
    max_metadata_bytes: 4096,
    max_body_bytes: 4096,
  }
  let schema = Schema::new([Field::new("a", Int64)])
  let batch = RecordBatch::new(schema, [Int64s([None, Some(9007199254740993L)])])
  for source in [write_stream(schema, [batch]), write_file(schema, [batch])] {
    for i in 0..<source.length() {
      let mutated = bytes_array(source)
      mutated[i] = (mutated[i].to_int() ^ 255).to_byte()
      let bytes = Bytes::from_array(mutated)
      // Mutations of padding or ordinary values can be valid. The property is
      // that parsing either succeeds or raises ArrowError, never panics.
      ignore(read_stream(bytes, limits~)) catch {
        _ => ()
      }
      ignore(read_file(bytes, limits~)) catch {
        _ => ()
      }
    }
  }
}
