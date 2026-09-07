///|
fn encode_metadata(out : Array[Byte], entries : Array[KeyValue]) -> Int {
  let vector = fb_vector(out, entries.length(), 4, 4)
  for i in 0..<entries.length() {
    let entry = entries[i]
    let table = fb_table(out, 2)
    let pointer = vector + 4 + i * 4
    put_i32(out, pointer, table.pos - pointer)
    fb_ref(out, table, 0, fb_string(out, entry.key))
    if entry.value is Some(value) {
      fb_ref(out, table, 1, fb_string(out, value))
    }
  }
  vector
}

///|
fn decode_metadata(
  data : Bytes,
  table : Int,
  slot : Int,
  limits : ReadLimits,
) -> Array[KeyValue] raise ArrowError {
  let (p, n) = vector_info(data, table, slot, 4, limits.max_fields)
  let result = []
  for i in 0..<n {
    let entry = follow_offset(data, p + i * 4)
    let key = read_string(data, required_ref(data, entry, 0))
    let value = match field_ref(data, entry, 1) {
      None => None
      Some(s) => Some(read_string(data, s))
    }
    result.push(KeyValue::{ key, value, })
  }
  result
}

///|
fn encode_schema(out : Array[Byte], schema : Schema) -> Int {
  let table = fb_table(out, 3)
  let fields = fb_vector(out, schema.fields.length(), 4, 4)
  fb_ref(out, table, 1, fields)
  for i in 0..<schema.fields.length() {
    let field = schema.fields[i]
    let f = fb_table(out, 7)
    let pointer = fields + 4 + i * 4
    put_i32(out, pointer, f.pos - pointer)
    fb_ref(out, f, 0, fb_string(out, field.name))
    fb_int(out, f, 1, if field.nullable { 1 } else { 0 })
    let (tag, width) = match field.data_type {
      Null => (1, 0)
      Int32 => (2, 32)
      Int64 => (2, 64)
      Float64 => (3, 0)
      Binary => (4, 0)
      Utf8 => (5, 0)
      Boolean => (6, 0)
    }
    fb_int(out, f, 2, tag)
    let t = fb_table(out, if tag == 2 { 2 } else if tag == 3 { 1 } else { 0 })
    fb_ref(out, f, 3, t.pos)
    if tag == 2 {
      fb_int(out, t, 0, width)
      fb_int(out, t, 1, 1)
    } else if tag == 3 {
      fb_int(out, t, 0, 2)
    }
    if !field.metadata.is_empty() {
      fb_ref(out, f, 6, encode_metadata(out, field.metadata))
    }
  }
  if !schema.metadata.is_empty() {
    fb_ref(out, table, 2, encode_metadata(out, schema.metadata))
  }
  table.pos
}

///|
fn decode_schema(
  data : Bytes,
  table : Int,
  limits : ReadLimits,
) -> Schema raise ArrowError {
  if field_int(data, table, 0, 2, 0) != 0 {
    raise Unsupported("big-endian schema")
  }
  let (_, features) = vector_info(data, table, 3, 8, limits.max_fields)
  if features != 0 {
    raise Unsupported("schema features (compression or dictionary replacement)")
  }
  let (p, n) = vector_info(data, table, 1, 4, limits.max_fields)
  let fields = []
  for i in 0..<n {
    let f = follow_offset(data, p + i * 4)
    let name = match field_ref(data, f, 0) {
      None => ""
      Some(s) => read_string(data, s)
    }
    let nullable = field_int(data, f, 1, 1, 0)
    if nullable > 1 {
      raise Invalid("invalid nullable flag")
    }
    if field_ref(data, f, 4) is Some(_) {
      raise Unsupported("dictionary encoding")
    }
    let (_, children) = vector_info(data, f, 5, 4, limits.max_fields)
    if children != 0 {
      raise Unsupported("nested fields")
    }
    let tag = field_int(data, f, 2, 1, 0)
    let t = required_ref(data, f, 3)
    // Validate even an empty type table before using its tag.
    ignore(table_field(data, t, 0, 1))
    let data_type = match tag {
      1 => DataType::Null
      2 => {
        if field_int(data, t, 1, 1, 0) != 1 {
          raise Unsupported("unsigned integers")
        }
        match field_int(data, t, 0, 4, 0) {
          32 => Int32
          64 => Int64
          _ => raise Unsupported("integer width (supports 32 and 64)")
        }
      }
      3 => {
        if field_int(data, t, 0, 2, 0) != 2 {
          raise Unsupported("floating-point precision (supports Float64)")
        }
        Float64
      }
      4 => Binary
      5 => Utf8
      6 => Boolean
      _ => raise Unsupported("Arrow type tag " + tag.to_string())
    }
    fields.push(Field::{
      name,
      data_type,
      nullable: nullable == 1,
      metadata: decode_metadata(data, f, 6, limits),
    })
  }
  { fields, metadata: decode_metadata(data, table, 2, limits), }
}

///|
priv struct BodyLayout {
  body : Bytes
  nodes : Array[(Int, Int)]
  buffers : Array[(Int, Int)]
}

///|
fn encode_batch_header(
  out : Array[Byte],
  rows : Int,
  layout : BodyLayout,
) -> Int {
  let table = fb_table(out, 3)
  fb_long(out, table, 0, rows.to_int64())
  let nodes = fb_vector(out, layout.nodes.length(), 16, 8)
  fb_ref(out, table, 1, nodes)
  for i in 0..<layout.nodes.length() {
    let (length, nulls) = layout.nodes[i]
    put_i64(out, nodes + 4 + i * 16, length.to_int64())
    put_i64(out, nodes + 12 + i * 16, nulls.to_int64())
  }
  let buffers = fb_vector(out, layout.buffers.length(), 16, 8)
  fb_ref(out, table, 2, buffers)
  for i in 0..<layout.buffers.length() {
    let (offset, length) = layout.buffers[i]
    put_i64(out, buffers + 4 + i * 16, offset.to_int64())
    put_i64(out, buffers + 12 + i * 16, length.to_int64())
  }
  table.pos
}

///|
fn schema_message(schema : Schema) -> Bytes {
  let out : Array[Byte] = [b'\x00', b'\x00', b'\x00', b'\x00']
  let message = fb_table(out, 4)
  put_i32(out, 0, message.pos)
  fb_int(out, message, 0, 4) // MetadataVersion::V5
  fb_int(out, message, 1, 1) // MessageHeader::Schema
  fb_ref(out, message, 2, encode_schema(out, schema))
  align_bytes(out, 8)
  Bytes::from_array(out)
}

///|
fn batch_message(rows : Int, layout : BodyLayout) -> Bytes {
  let out : Array[Byte] = [b'\x00', b'\x00', b'\x00', b'\x00']
  let message = fb_table(out, 4)
  put_i32(out, 0, message.pos)
  fb_int(out, message, 0, 4)
  fb_int(out, message, 1, 3) // MessageHeader::RecordBatch
  fb_long(out, message, 3, layout.body.length().to_int64())
  fb_ref(out, message, 2, encode_batch_header(out, rows, layout))
  align_bytes(out, 8)
  Bytes::from_array(out)
}

///|
priv struct Frame {
  metadata : Bytes
  header : Int
  kind : Int
  body : Bytes
  next : Int
  metadata_size : Int
}

///|
fn read_frame(
  data : Bytes,
  start : Int,
  end : Int,
  limits : ReadLimits,
) -> Frame? raise ArrowError {
  if start < 0 || end > data.length() || start > end {
    raise Invalid("invalid frame boundary")
  }
  if start == end {
    return None
  }
  if end - start < 4 {
    raise Invalid("truncated IPC prefix")
  }
  let first = read_i32(data, start)
  let prefix = if first == -1 { 8 } else { 4 }
  if end - start < prefix {
    raise Invalid("truncated IPC continuation")
  }
  let size = if prefix == 8 { read_i32(data, start + 4) } else { first }
  if size == 0 {
    if start + prefix != end {
      raise Invalid("bytes after end-of-stream marker")
    }
    return None
  }
  if size < 0 {
    raise Invalid("negative metadata size")
  }
  if size > limits.max_metadata_bytes {
    raise LimitExceeded("metadata size")
  }
  if size > end - start - prefix {
    raise Invalid("truncated IPC metadata")
  }
  let metadata = slice_bytes(data, start + prefix, size)
  let root = follow_offset(metadata, 0)
  let version = field_int(metadata, root, 0, 2, 0)
  if version != 3 && version != 4 {
    raise Unsupported("IPC metadata version")
  }
  let kind = field_int(metadata, root, 1, 1, 0)
  let header = required_ref(metadata, root, 2)
  let body_size = bounded_i64(
    field_long(metadata, root, 3),
    limits.max_body_bytes,
    "body size",
  )
  let body_start = start + prefix + size
  if body_size > end - body_start {
    raise Invalid("truncated IPC body")
  }
  if kind == 1 && body_size != 0 {
    raise Invalid("schema message has a body")
  }
  // Per-message metadata has no public representation yet: fail rather than lose it.
  let (_, custom) = vector_info(metadata, root, 4, 4, limits.max_fields)
  if custom != 0 {
    raise Unsupported("per-message custom metadata")
  }
  Some({
    metadata,
    header,
    kind,
    body: slice_bytes(data, body_start, body_size),
    next: body_start + body_size,
    metadata_size: prefix + size,
  })
}
