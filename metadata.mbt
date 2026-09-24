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
fn encode_field(out : Array[Byte], field : Field) -> Int {
    let f = fb_table(out, 7)
    fb_ref(out, f, 0, fb_string(out, field.name))
    fb_int(out, f, 1, if field.nullable { 1 } else { 0 })
    let value_type = match field.data_type {
      Dictionary(_, inner, _) => inner
      other => other
    }
    let (tag, width, signed) = match value_type {
      Null => (1, 0, 0)
      Int8 => (2, 8, 1)
      Int16 => (2, 16, 1)
      Int32 => (2, 32, 1)
      Int64 => (2, 64, 1)
      UInt8 => (2, 8, 0)
      UInt16 => (2, 16, 0)
      UInt32 => (2, 32, 0)
      UInt64 => (2, 64, 0)
      Float32 => (3, 1, 0)
      Float64 => (3, 2, 0)
      Date32 => (8, 0, 0)
      Date64 => (8, 1, 0)
      Timestamp(_, _) => (10, 0, 0)
      Duration(_) => (18, 0, 0)
      List => (12, 0, 0)
      Struct => (13, 0, 0)
      Dictionary(_, _, _) => (0, 0, 0)
      Binary => (4, 0, 0)
      Utf8 => (5, 0, 0)
      Boolean => (6, 0, 0)
    }
    fb_int(out, f, 2, tag)
    let t = fb_table(out, if tag == 2 || tag == 10 { 2 } else if tag == 3 || tag == 8 || tag == 18 { 1 } else { 0 })
    fb_ref(out, f, 3, t.pos)
    if tag == 2 {
      fb_int(out, t, 0, width)
      fb_int(out, t, 1, signed)
    } else if tag == 3 {
      fb_int(out, t, 0, width)
    } else if tag == 8 {
      fb_int(out, t, 0, width)
    } else if tag == 10 {
      if value_type is Timestamp(unit, timezone) {
        fb_int(out, t, 0, time_unit_code(unit))
        if timezone is Some(name) {
          fb_ref(out, t, 1, fb_string(out, name))
        }
      }
    } else if tag == 18 {
      if value_type is Duration(unit) {
        fb_int(out, t, 0, time_unit_code(unit))
      }
    }
    if field.data_type is Dictionary(id, _, ordered) {
      let dictionary = fb_table(out, 4)
      fb_ref(out, f, 4, dictionary.pos)
      fb_long(out, dictionary, 0, id)
      let index_type = fb_table(out, 2)
      fb_ref(out, dictionary, 1, index_type.pos)
      fb_int(out, index_type, 0, 32)
      fb_int(out, index_type, 1, 1)
      fb_int(out, dictionary, 2, if ordered { 1 } else { 0 })
    }
    if !field.metadata.is_empty() {
      fb_ref(out, f, 6, encode_metadata(out, field.metadata))
    }
    if !field.children.is_empty() {
      let children = fb_vector(out, field.children.length(), 4, 4)
      fb_ref(out, f, 5, children)
      for i in 0..<field.children.length() {
        let pointer = children + 4 + i * 4
        let child = encode_field(out, field.children[i])
        put_i32(out, pointer, child - pointer)
      }
    }
    f.pos
}

///|
fn encode_schema(out : Array[Byte], schema : Schema, replacement? : Bool = false) -> Int {
  let table = fb_table(out, 4)
  let fields = fb_vector(out, schema.fields.length(), 4, 4)
  fb_ref(out, table, 1, fields)
  for i in 0..<schema.fields.length() {
    let pointer = fields + 4 + i * 4
    let field = encode_field(out, schema.fields[i])
    put_i32(out, pointer, field - pointer)
  }
  if !schema.metadata.is_empty() {
    fb_ref(out, table, 2, encode_metadata(out, schema.metadata))
  }
  if replacement {
    let features = fb_vector(out, 1, 8, 8)
    fb_ref(out, table, 3, features)
    put_i64(out, features + 4, 1L)
  }
  table.pos
}

///|
fn decode_field(data : Bytes, f : Int, limits : ReadLimits, depth : Int) -> (Field, Int) raise ArrowError {
    if depth > limits.max_depth { raise LimitExceeded("nested field depth") }
    let name = match field_ref(data, f, 0) {
      None => ""
      Some(s) => read_string(data, s)
    }
    let nullable = field_int(data, f, 1, 1, 0)
    if nullable > 1 {
      raise Invalid("invalid nullable flag")
    }
    let tag = field_int(data, f, 2, 1, 0)
    let t = required_ref(data, f, 3)
    // Validate even an empty type table before using its tag.
    ignore(table_field(data, t, 0, 1))
    let value_type = match tag {
      1 => DataType::Null
      2 => {
        let signed = field_int(data, t, 1, 1, 0)
        if signed > 1 { raise Invalid("invalid integer signedness") }
        match (field_int(data, t, 0, 4, 0), signed) {
          (8, 1) => Int8
          (16, 1) => Int16
          (32, 1) => Int32
          (64, 1) => Int64
          (8, 0) => UInt8
          (16, 0) => UInt16
          (32, 0) => UInt32
          (64, 0) => UInt64
          _ => raise Unsupported("integer width")
        }
      }
      3 => match field_int(data, t, 0, 2, 0) {
        1 => Float32
        2 => Float64
        _ => raise Unsupported("floating-point precision")
        }
      4 => Binary
      5 => Utf8
      6 => Boolean
      8 => match field_int(data, t, 0, 2, 1) {
        0 => Date32
        1 => Date64
        _ => raise Unsupported("date unit")
      }
      10 => Timestamp(
        decode_time_unit(field_int(data, t, 0, 2, 0)),
        match field_ref(data, t, 1) {
          None => None
          Some(p) => Some(read_string(data, p))
        },
      )
      18 => Duration(decode_time_unit(field_int(data, t, 0, 2, 1)))
      12 => List
      13 => Struct
      _ => raise Unsupported("Arrow type tag " + tag.to_string())
    }
    let data_type = match field_ref(data, f, 4) {
      None => value_type
      Some(dictionary) => {
        if value_type != Utf8 && value_type != Binary {
          raise Unsupported("dictionary value type")
        }
        let index = required_ref(data, dictionary, 1)
        if field_int(data, index, 0, 4, 0) != 32 ||
          field_int(data, index, 1, 1, 0) != 1 {
          raise Unsupported("dictionary index type")
        }
        let ordered = field_int(data, dictionary, 2, 1, 0)
        if ordered > 1 || field_int(data, dictionary, 3, 2, 0) != 0 {
          raise Unsupported("dictionary ordering or kind")
        }
        Dictionary(field_long(data, dictionary, 0), value_type, ordered == 1)
      }
    }
    let (p, n) = vector_info(data, f, 5, 4, limits.max_fields)
    if (data_type == List && n != 1) ||
      (data_type != List && data_type != Struct && n != 0) {
      raise Invalid("invalid child field count")
    }
    let children = []
    let mut total = 1
    for i in 0..<n {
      let (child, used) = decode_field(data, follow_offset(data, p + i * 4), limits, depth + 1)
      if used > limits.max_fields - total { raise LimitExceeded("total field count") }
      total += used
      children.push(child)
    }
    (Field::{
      name,
      data_type,
      nullable: nullable == 1,
      metadata: decode_metadata(data, f, 6, limits),
      children,
    }, total)
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
  let (feature_base, features) = vector_info(data, table, 3, 8, limits.max_fields)
  for i in 0..<features {
    if read_i64(data, feature_base + i * 8) != 1L {
      raise Unsupported("schema feature")
    }
  }
  let (p, n) = vector_info(data, table, 1, 4, limits.max_fields)
  let fields = []
  let mut total = 0
  for i in 0..<n {
    let (field, used) = decode_field(data, follow_offset(data, p + i * 4), limits, 0)
    if used > limits.max_fields - total { raise LimitExceeded("total field count") }
    total += used
    fields.push(field)
  }
  { fields, metadata: decode_metadata(data, table, 2, limits), }
}

///|
fn time_unit_code(unit : TimeUnit) -> Int {
  match unit {
    Second => 0
    Millisecond => 1
    Microsecond => 2
    Nanosecond => 3
  }
}

///|
fn decode_time_unit(code : Int) -> TimeUnit raise ArrowError {
  match code {
    0 => Second
    1 => Millisecond
    2 => Microsecond
    3 => Nanosecond
    _ => raise Unsupported("time unit")
  }
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
fn schema_message(schema : Schema, replacement? : Bool = false) -> Bytes {
  let out : Array[Byte] = [b'\x00', b'\x00', b'\x00', b'\x00']
  let message = fb_table(out, 4)
  put_i32(out, 0, message.pos)
  fb_int(out, message, 0, 4) // MetadataVersion::V5
  fb_int(out, message, 1, 1) // MessageHeader::Schema
  fb_ref(out, message, 2, encode_schema(out, schema, replacement~))
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
