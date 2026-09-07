///|
fn check_range(data : Bytes, offset : Int, size : Int) -> Unit raise ArrowError {
  if offset < 0 ||
    size < 0 ||
    offset > data.length() ||
    size > data.length() - offset {
    raise Invalid("byte range outside input")
  }
}

///|
fn read_u8(data : Bytes, p : Int) -> Int raise ArrowError {
  check_range(data, p, 1)
  data[p].to_int()
}

///|
fn read_u16(data : Bytes, p : Int) -> Int raise ArrowError {
  check_range(data, p, 2)
  data[p].to_int() | (data[p + 1].to_int() << 8)
}

///|
fn read_i32(data : Bytes, p : Int) -> Int raise ArrowError {
  check_range(data, p, 4)
  data[p].to_int() |
  (data[p + 1].to_int() << 8) |
  (data[p + 2].to_int() << 16) |
  (data[p + 3].to_int() << 24)
}

///|
fn read_i64(data : Bytes, p : Int) -> Int64 raise ArrowError {
  check_range(data, p, 8)
  let mut value = 0L
  for i in 0..<8 {
    value = value | (data[p + i].to_int().to_int64() << (8 * i))
  }
  value
}

///|
fn bounded_i64(
  value : Int64,
  limit : Int,
  what : String,
) -> Int raise ArrowError {
  if value < 0L {
    raise Invalid("negative " + what)
  }
  if value > limit.to_int64() {
    raise LimitExceeded(what)
  }
  value.to_int()
}

///|
fn slice_bytes(data : Bytes, p : Int, size : Int) -> Bytes raise ArrowError {
  check_range(data, p, size)
  data.view(start=p, end=p + size).to_owned()
}

///|
fn decode_utf8(data : Bytes, p : Int, n : Int) -> String raise ArrowError {
  check_range(data, p, n)
  @utf8.decode(data.view(start=p, end=p + n), ignore_bom=false) catch {
    _ => raise Invalid("invalid UTF-8")
  }
}

///|
fn put_u16(out : Array[Byte], p : Int, value : Int) -> Unit {
  for i in 0..<2 {
    out[p + i] = ((value >> (8 * i)) & 255).to_byte()
  }
}

///|
fn put_i32(out : Array[Byte], p : Int, value : Int) -> Unit {
  for i in 0..<4 {
    out[p + i] = ((value >> (8 * i)) & 255).to_byte()
  }
}

///|
fn put_i64(out : Array[Byte], p : Int, value : Int64) -> Unit {
  for i in 0..<8 {
    out[p + i] = ((value >> (8 * i)) & 255L).to_byte()
  }
}

///|
fn reserve(out : Array[Byte], n : Int) -> Int {
  let start = out.length()
  for _ in 0..<n {
    out.push(b'\x00')
  }
  start
}

///|
fn align_bytes(out : Array[Byte], alignment : Int) -> Unit {
  while out.length() % alignment != 0 {
    out.push(b'\x00')
  }
}

///|
fn append_bytes(out : Array[Byte], data : Bytes) -> Unit {
  for b in data {
    out.push(b)
  }
}

///|
/// A private, forward-building FlatBuffer codec for Arrow metadata only.
/// Every table slot occupies eight bytes so all scalar types are aligned.
priv struct FbTable {
  pos : Int
  vtable : Int
}

///|
fn fb_table(out : Array[Byte], slots : Int) -> FbTable {
  align_bytes(out, 2)
  let vtable = reserve(out, 4 + 2 * slots)
  align_bytes(out, 8)
  let pos = reserve(out, 8 + 8 * slots)
  put_u16(out, vtable, 4 + 2 * slots)
  put_u16(out, vtable + 2, 8 + 8 * slots)
  put_i32(out, pos, pos - vtable)
  { pos, vtable, }
}

///|
fn fb_slot(out : Array[Byte], table : FbTable, slot : Int) -> Int {
  let offset = 8 + 8 * slot
  put_u16(out, table.vtable + 4 + slot * 2, offset)
  table.pos + offset
}

///|
fn fb_int(out : Array[Byte], table : FbTable, slot : Int, value : Int) -> Unit {
  put_i32(out, fb_slot(out, table, slot), value)
}

///|
fn fb_long(
  out : Array[Byte],
  table : FbTable,
  slot : Int,
  value : Int64,
) -> Unit {
  put_i64(out, fb_slot(out, table, slot), value)
}

///|
fn fb_ref(out : Array[Byte], table : FbTable, slot : Int, target : Int) -> Unit {
  let p = fb_slot(out, table, slot)
  put_i32(out, p, target - p)
}

///|
fn fb_string(out : Array[Byte], value : String) -> Int {
  let bytes = @utf8.encode(value)
  align_bytes(out, 4)
  let pos = reserve(out, 4)
  put_i32(out, pos, bytes.length())
  append_bytes(out, bytes)
  out.push(b'\x00')
  pos
}

///|
fn fb_vector(
  out : Array[Byte],
  count : Int,
  width : Int,
  alignment : Int,
) -> Int {
  align_bytes(out, 4)
  while (out.length() + 4) % alignment != 0 {
    out.push(b'\x00')
  }
  let p = reserve(out, 4 + count * width)
  put_i32(out, p, count)
  p
}

///|
fn follow_offset(data : Bytes, p : Int) -> Int raise ArrowError {
  let n = read_i32(data, p)
  if n < 4 || n > data.length() - p {
    raise Invalid("invalid FlatBuffer offset")
  }
  let target = p + n
  check_range(data, target, 1)
  target
}

///|
fn table_field(
  data : Bytes,
  table : Int,
  slot : Int,
  size : Int,
) -> Int? raise ArrowError {
  let displacement = read_i32(data, table).to_int64()
  let v64 = table.to_int64() - displacement
  if displacement == 0L || v64 < 0L || v64 > data.length().to_int64() {
    raise Invalid("invalid FlatBuffer vtable")
  }
  let v = v64.to_int()
  let vsize = read_u16(data, v)
  let object_size = read_u16(data, v + 2)
  if vsize < 4 || vsize % 2 != 0 || object_size < 4 {
    raise Invalid("invalid FlatBuffer table size")
  }
  check_range(data, v, vsize)
  check_range(data, table, object_size)
  if slot >= (vsize - 4) / 2 {
    return None
  }
  let offset = read_u16(data, v + 4 + slot * 2)
  if offset == 0 {
    return None
  }
  if offset < 4 || size > object_size - offset {
    raise Invalid("FlatBuffer field outside table")
  }
  Some(table + offset)
}

///|
fn field_int(
  data : Bytes,
  table : Int,
  slot : Int,
  size : Int,
  default : Int,
) -> Int raise ArrowError {
  match table_field(data, table, slot, size) {
    None => default
    Some(p) =>
      match size {
        1 => read_u8(data, p)
        2 => read_u16(data, p)
        _ => read_i32(data, p)
      }
  }
}

///|
fn field_long(data : Bytes, table : Int, slot : Int) -> Int64 raise ArrowError {
  match table_field(data, table, slot, 8) {
    None => 0L
    Some(p) => read_i64(data, p)
  }
}

///|
fn field_ref(data : Bytes, table : Int, slot : Int) -> Int? raise ArrowError {
  match table_field(data, table, slot, 4) {
    None => None
    Some(p) => Some(follow_offset(data, p))
  }
}

///|
fn required_ref(data : Bytes, table : Int, slot : Int) -> Int raise ArrowError {
  match field_ref(data, table, slot) {
    Some(p) => p
    None => raise Invalid("missing required FlatBuffer field")
  }
}

///|
fn read_string(data : Bytes, p : Int) -> String raise ArrowError {
  let n = read_i32(data, p)
  if n < 0 || n >= data.length() - p - 4 {
    raise Invalid("invalid string length")
  }
  if read_u8(data, p + 4 + n) != 0 {
    raise Invalid("unterminated FlatBuffer string")
  }
  decode_utf8(data, p + 4, n)
}

///|
fn vector_info(
  data : Bytes,
  table : Int,
  slot : Int,
  width : Int,
  limit : Int,
) -> (Int, Int) raise ArrowError {
  match field_ref(data, table, slot) {
    None => (0, 0)
    Some(p) => {
      let n = read_i32(data, p)
      if n < 0 {
        raise Invalid("negative vector length")
      }
      if n > limit {
        raise LimitExceeded("metadata vector length")
      }
      if n > (data.length() - p - 4) / width {
        raise Invalid("truncated vector")
      }
      (p + 4, n)
    }
  }
}
