///|
fn hex(bytes : Bytes) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  for byte in bytes {
    out.write_char(digits[byte.to_int() >> 4].to_char().unwrap())
    out.write_char(digits[byte.to_int() & 15].to_char().unwrap())
  }
  out.to_string()
}

///|
fn nibble(c : Char) -> Int raise {
  if c >= '0' && c <= '9' {
    return c.to_int() - '0'.to_int()
  }
  if c >= 'a' && c <= 'f' {
    return c.to_int() - 'a'.to_int() + 10
  }
  if c >= 'A' && c <= 'F' {
    return c.to_int() - 'A'.to_int() + 10
  }
  fail("invalid hexadecimal input")
}

///|
fn unhex(s : String) -> Bytes raise {
  if s.length() % 2 != 0 {
    fail("odd hexadecimal input")
  }
  let out : Array[Byte] = []
  for i in 0..<(s.length() / 2) {
    out.push(
      ((nibble(s[i * 2].to_char().unwrap()) << 4) |
      nibble(s[i * 2 + 1].to_char().unwrap())).to_byte(),
    )
  }
  Bytes::from_array(out)
}

///|
fn metadata_json(entries : Array[@arrow.KeyValue]) -> Json {
  entries
  .map(entry => {
    Json::array([
      Json::string(entry.key),
      match entry.value {
        Some(v) => Json::string(v)
        None => Json::null()
      },
    ])
  })
  .to_json()
}

///|
fn time_unit_string(unit : @arrow.TimeUnit) -> String {
  match unit {
    Second => "s"
    Millisecond => "ms"
    Microsecond => "us"
    Nanosecond => "ns"
  }
}

///|
fn field_type_string(field : @arrow.Field) -> String {
  match field.data_type {
    Null => "null"
    Boolean => "bool"
    Int8 => "int8"
    Int16 => "int16"
    Int32 => "int32"
    Int64 => "int64"
    UInt8 => "uint8"
    UInt16 => "uint16"
    UInt32 => "uint32"
    UInt64 => "uint64"
    Float32 => "float"
    Float64 => "double"
    Date32 => "date32[day]"
    Date64 => "date64[ms]"
    Timestamp(unit, timezone) => "timestamp[" + time_unit_string(unit) + (match timezone {
      Some(s) => ", tz=" + s
      None => ""
    }) + "]"
    Duration(unit) => "duration[" + time_unit_string(unit) + "]"
    Utf8 => "string"
    Binary => "binary"
    List => "list<" + child_type_string(field.children[0]) + ">"
    Struct => {
      let parts = field.children.map(child => child_type_string(child))
      "struct<" + parts.join(", ") + ">"
    }
  }
}

///|
fn child_type_string(field : @arrow.Field) -> String {
  field.name + ": " + field_type_string(field) +
  (if field.nullable { "" } else { " not null" })
}

///|
fn schema_json(schema : @arrow.Schema) -> Json {
  let fields = schema.fields.map(field => {
    let kind = field_type_string(field)
    Json::object({
      "name": field.name.to_json(),
      "type": kind.to_json(),
      "nullable": field.nullable.to_json(),
      "metadata": metadata_json(field.metadata),
    })
  })
  { "fields": fields.to_json(), "metadata": metadata_json(schema.metadata) }
}

///|
fn cell_json(column : @arrow.Column, field : @arrow.Field, i : Int) -> Json {
  match column {
    Nulls(_) => Json::null()
    Booleans(a) => match a[i] {
      Some(x) => x.to_json()
      None => Json::null()
    }
    Int8s(a) | Int16s(a) | Int32s(a) |
    UInt8s(a) | UInt16s(a) | Date32s(a) =>
      match a[i] {
        Some(x) => x.to_json()
        None => Json::null()
      }
    Int64s(a) | Date64s(a) | Timestamps(a, _, _) | Durations(a, _) =>
      match a[i] {
        Some(x) => Json::string(x.to_string())
        None => Json::null()
      }
    UInt32s(a) => match a[i] {
      Some(x) => x.to_json()
      None => Json::null()
    }
    UInt64s(a) => match a[i] {
      Some(x) => Json::string(x.to_string())
      None => Json::null()
    }
    Float32s(a) => match a[i] {
      Some(x) => Json::string(x.reinterpret_as_int().to_string())
      None => Json::null()
    }
    Float64s(a) => match a[i] {
      Some(x) => Json::string(x.reinterpret_as_int64().to_string())
      None => Json::null()
    }
    Strings(a) => match a[i] {
      Some(x) => x.to_json()
      None => Json::null()
    }
    Binaries(a) => match a[i] {
      Some(x) => Json::string(hex(x))
      None => Json::null()
    }
    Lists(offsets, validity, child) => {
      if !validity[i] { return Json::null() }
      let items = []
      for j in offsets[i]..<offsets[i + 1] {
        items.push(cell_json(child, field.children[0], j))
      }
      Json::array(items)
    }
    Structs(validity, children) => {
      if !validity[i] { return Json::null() }
      let members : Map[String, Json] = Map([])
      for j in 0..<children.length() {
        members[field.children[j].name] = cell_json(children[j], field.children[j], i)
      }
      Json::object(members)
    }
  }
}

///|
fn column_json(column : @arrow.Column, field : @arrow.Field) -> Json {
  Array::makei(column.length(), i => cell_json(column, field, i)).to_json()
}

///|
fn data_json(data : @arrow.IpcData) -> Json {
  let batches = data.batches.map(batch => {
    Json::object({
      "rows": batch.num_rows.to_json(),
      "columns": Array::makei(batch.columns.length(), i =>
        column_json(batch.columns[i], data.schema.fields[i])).to_json(),
    })
  })
  { "schema": schema_json(data.schema), "batches": batches.to_json() }
}

///|
fn sample() -> @arrow.IpcData raise {
  let schema = @arrow.Schema::new(
    [
      @arrow.Field::new("id", Int64),
      @arrow.Field::new("value", Float64),
      @arrow.Field::new("name", Utf8, metadata=[
        { key: "unit", value: Some("文本"), },
      ]),
      @arrow.Field::new("payload", Binary),
      @arrow.Field::new("flag", Boolean),
      @arrow.Field::new("count", Int32),
      @arrow.Field::new("empty", Null),
    ],
    metadata=[{ key: "producer", value: Some("MoonBit"), }],
  )
  let first = @arrow.RecordBatch::new(schema, [
    Int64s([
      Some(-9223372036854775808L),
      Some(9223372036854775807L),
      None,
      Some(9007199254740993L),
    ]),
    Float64s([
      Some(-0.0),
      Some(1.5),
      None,
      Some(0x7ff0000000000000L.reinterpret_as_double()),
    ]),
    Strings([
      Some("月兔🐇"),
      Some(""),
      None,
      Some("\u{FEFF}bom\u{0000}tail"),
    ]),
    Binaries([Some(b"\xff\x00"), None, Some(b""), Some(b"ARROW1")]),
    Booleans([Some(true), Some(false), None, Some(true)]),
    Int32s([Some(-2147483648), None, Some(2147483647), Some(0)]),
    Nulls(4),
  ])
  let second = @arrow.RecordBatch::new(schema, [
    Int64s([]),
    Float64s([]),
    Strings([]),
    Binaries([]),
    Booleans([]),
    Int32s([]),
    Nulls(0),
  ])
  @arrow.read_stream(@arrow.write_stream(schema, [first, second]))
}

///|
/// Hex transport keeps this test executable portable and free of filesystem FFI.
fn main {
  let args = @env.args()
  let result = try {
    // Native argv includes the executable; Node argv also includes the script.
    let data = match args {
      [_, "sample"] | [_, _, "sample"] => sample()
      [_, "stream", raw] | [_, _, "stream", raw] =>
        @arrow.read_stream(unhex(raw))
      [_, "file", raw] | [_, _, "file", raw] => @arrow.read_file(unhex(raw))
      _ => fail("usage: interop sample | stream HEX | file HEX")
    }
    Json::object({
      "data": data_json(data),
      "stream": hex(@arrow.write_stream(data.schema, data.batches)).to_json(),
      "file": hex(@arrow.write_file(data.schema, data.batches)).to_json(),
    })
  } catch {
    error => Json::object({ "error": error.to_string().to_json() })
  }
  println(result.stringify())
}
