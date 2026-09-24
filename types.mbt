///|
/// Errors for malformed input, unsupported features, and invalid batches.
pub(all) suberror ArrowError {
  Invalid(String)
  Unsupported(String)
  LimitExceeded(String)
} derive(Debug)

///|
/// Resolution of a timestamp or duration. No timezone conversion is implied.
pub(all) enum TimeUnit {
  Second
  Millisecond
  Microsecond
  Nanosecond
} derive(Eq, Debug)

///|
/// Types supported by the initial IPC implementation.
pub(all) enum DataType {
  Null
  Boolean
  Int8
  Int16
  Int32
  Int64
  UInt8
  UInt16
  UInt32
  UInt64
  Float32
  Float64
  Date32
  Date64
  Timestamp(TimeUnit, String?)
  Duration(TimeUnit)
  List
  Struct
  Dictionary(Int64, DataType, Bool)
  Utf8
  Binary
} derive(Eq, Debug)

///|
/// UTF-8 key/value metadata. Order and duplicate keys are preserved.
pub(all) struct KeyValue {
  key : String
  value : String?
} derive(Eq, Debug)

///|
/// A named field. Extension metadata is preserved without interpreting it.
pub(all) struct Field {
  name : String
  data_type : DataType
  nullable : Bool
  metadata : Array[KeyValue]
  children : Array[Field]
} derive(Eq, Debug)

///|
pub fn Field::new(
  name : String,
  data_type : DataType,
  nullable? : Bool = true,
  metadata? : Array[KeyValue] = [],
  children? : Array[Field] = [],
) -> Field {
  { name, data_type, nullable, metadata, children, }
}

///|
/// A schema, including ordered custom metadata.
pub(all) struct Schema {
  fields : Array[Field]
  metadata : Array[KeyValue]
} derive(Eq, Debug)

///|
pub fn Schema::new(
  fields : Array[Field],
  metadata? : Array[KeyValue] = [],
) -> Schema {
  { fields, metadata, }
}

///|
/// Owned, decoded column values. None represents an Arrow null slot.
/// Binary data is never interpreted as text; Int64 values retain all 64 bits.
pub(all) enum Column {
  Nulls(Int)
  Booleans(Array[Bool?])
  Int8s(Array[Int?])
  Int16s(Array[Int?])
  Int32s(Array[Int?])
  Int64s(Array[Int64?])
  UInt8s(Array[Int?])
  UInt16s(Array[Int?])
  UInt32s(Array[UInt?])
  UInt64s(Array[UInt64?])
  Float32s(Array[Float?])
  Float64s(Array[Double?])
  Date32s(Array[Int?])
  Date64s(Array[Int64?])
  Timestamps(Array[Int64?], TimeUnit, String?)
  Durations(Array[Int64?], TimeUnit)
  Lists(Array[Int], Array[Bool], Column)
  Structs(Array[Bool], Array[Column])
  Dictionaries(Array[Int?], Column, Int64, Bool)
  Strings(Array[String?])
  Binaries(Array[Bytes?])
} derive(Debug)

///|
pub fn Column::length(self : Column) -> Int {
  match self {
    Nulls(n) => n
    Booleans(a) => a.length()
    Int8s(a) => a.length()
    Int16s(a) => a.length()
    Int32s(a) => a.length()
    Int64s(a) => a.length()
    UInt8s(a) => a.length()
    UInt16s(a) => a.length()
    UInt32s(a) => a.length()
    UInt64s(a) => a.length()
    Float32s(a) => a.length()
    Float64s(a) => a.length()
    Date32s(a) => a.length()
    Date64s(a) => a.length()
    Timestamps(a, _, _) => a.length()
    Durations(a, _) => a.length()
    Lists(offsets, _, _) => offsets.length() - 1
    Structs(validity, _) => validity.length()
    Dictionaries(indices, _, _, _) => indices.length()
    Strings(a) => a.length()
    Binaries(a) => a.length()
  }
}

///|
pub fn Column::data_type(self : Column) -> DataType {
  match self {
    Nulls(_) => Null
    Booleans(_) => Boolean
    Int8s(_) => Int8
    Int16s(_) => Int16
    Int32s(_) => Int32
    Int64s(_) => Int64
    UInt8s(_) => UInt8
    UInt16s(_) => UInt16
    UInt32s(_) => UInt32
    UInt64s(_) => UInt64
    Float32s(_) => Float32
    Float64s(_) => Float64
    Date32s(_) => Date32
    Date64s(_) => Date64
    Timestamps(_, unit, timezone) => Timestamp(unit, timezone)
    Durations(_, unit) => Duration(unit)
    Lists(_, _, _) => List
    Structs(_, _) => Struct
    Dictionaries(_, values, id, ordered) => Dictionary(id, values.data_type(), ordered)
    Strings(_) => Utf8
    Binaries(_) => Binary
  }
}

///|
fn Column::valid_at(self : Column, i : Int) -> Bool {
  match self {
    Nulls(_) => false
    Booleans(a) => a[i] is Some(_)
    Int8s(a) => a[i] is Some(_)
    Int16s(a) => a[i] is Some(_)
    Int32s(a) => a[i] is Some(_)
    Int64s(a) => a[i] is Some(_)
    UInt8s(a) => a[i] is Some(_)
    UInt16s(a) => a[i] is Some(_)
    UInt32s(a) => a[i] is Some(_)
    UInt64s(a) => a[i] is Some(_)
    Float32s(a) => a[i] is Some(_)
    Float64s(a) => a[i] is Some(_)
    Date32s(a) => a[i] is Some(_)
    Date64s(a) => a[i] is Some(_)
    Timestamps(a, _, _) => a[i] is Some(_)
    Durations(a, _) => a[i] is Some(_)
    Lists(_, validity, _) => validity[i]
    Structs(validity, _) => validity[i]
    Dictionaries(indices, _, _, _) => indices[i] is Some(_)
    Strings(a) => a[i] is Some(_)
    Binaries(a) => a[i] is Some(_)
  }
}

///|
pub fn Column::null_count(self : Column) -> Int {
  let mut count = 0
  for i in 0..<self.length() {
    if !self.valid_at(i) {
      count += 1
    }
  }
  count
}

///|
/// A batch of equal-length columns. Writers revalidate mutable column arrays.
pub struct RecordBatch {
  schema : Schema
  columns : Array[Column]
  num_rows : Int
} derive(Debug)

///|
/// num_rows is required only to represent nonzero rows with zero columns.
pub fn RecordBatch::new(
  schema : Schema,
  columns : Array[Column],
  num_rows? : Int,
) -> RecordBatch raise ArrowError {
  let rows = match num_rows {
    Some(n) => n
    None => if columns.is_empty() { 0 } else { columns[0].length() }
  }
  let batch = { schema, columns, num_rows: rows, }
  batch.validate()
  batch
}

///|
pub fn RecordBatch::validate(self : RecordBatch) -> Unit raise ArrowError {
  if self.num_rows < 0 {
    raise Invalid("negative row count")
  }
  if self.columns.length() != self.schema.fields.length() {
    raise Invalid("column count does not match schema")
  }
  for i in 0..<self.columns.length() {
    let field = self.schema.fields[i]
    let column = self.columns[i]
    if column.length() != self.num_rows {
      raise Invalid("column length mismatch: " + field.name)
    }
    if column.data_type() != field.data_type {
      raise Invalid("column type mismatch: " + field.name)
    }
    if !field.nullable && column.null_count() != 0 {
      raise Invalid("null in non-nullable field: " + field.name)
    }
    validate_nested(field, column, 0)
    match column {
      Int8s(a) => for v in a { if v is Some(x) && (x < -128 || x > 127) { raise Invalid("Int8 value outside range: " + field.name) } }
      Int16s(a) => for v in a { if v is Some(x) && (x < -32768 || x > 32767) { raise Invalid("Int16 value outside range: " + field.name) } }
      UInt8s(a) => for v in a { if v is Some(x) && (x < 0 || x > 255) { raise Invalid("UInt8 value outside range: " + field.name) } }
      UInt16s(a) => for v in a { if v is Some(x) && (x < 0 || x > 65535) { raise Invalid("UInt16 value outside range: " + field.name) } }
      Date64s(a) => for v in a { if v is Some(x) && x % 86400000L != 0L { raise Invalid("Date64 must be whole days: " + field.name) } }
      _ => ()
    }
  }
}

///|
fn validate_nested(field : Field, column : Column, depth : Int) -> Unit raise ArrowError {
  if depth > 64 { raise LimitExceeded("nested depth") }
  match (field.data_type, column) {
    (List, Lists(offsets, validity, child)) => {
      if field.children.length() != 1 || offsets.length() != validity.length() + 1 {
        raise Invalid("invalid List field or offsets")
      }
      if offsets.is_empty() || offsets[0] < 0 || offsets[0] > child.length() {
        raise Invalid("invalid first List offset")
      }
      for i in 0..<validity.length() {
        if offsets[i + 1] < offsets[i] || offsets[i + 1] > child.length() {
          raise Invalid("invalid List offsets")
        }
      }
      if child.data_type() != field.children[0].data_type ||
        (!field.children[0].nullable && child.null_count() != 0) {
        raise Invalid("List child type or nullability mismatch")
      }
      validate_nested(field.children[0], child, depth + 1)
    }
    (Struct, Structs(validity, children)) => {
      if field.children.length() != children.length() {
        raise Invalid("Struct child count mismatch")
      }
      for i in 0..<children.length() {
        let child = children[i]
        let child_field = field.children[i]
        if child.length() != validity.length() || child.data_type() != child_field.data_type ||
          (!child_field.nullable && child.null_count() != 0) {
          raise Invalid("Struct child length, type or nullability mismatch")
        }
        validate_nested(child_field, child, depth + 1)
      }
    }
    (Dictionary(_, value_type, _), Dictionaries(indices, values, _, _)) => {
      if (value_type != Utf8 && value_type != Binary) || values.data_type() != value_type {
        raise Unsupported("dictionary values must be Utf8 or Binary")
      }
      for index in indices {
        if index is Some(i) && (i < 0 || i >= values.length()) {
          raise Invalid("dictionary index outside values")
        }
      }
    }
    (List, _) | (Struct, _) => raise Invalid("nested column type mismatch")
    (_, _) => if !field.children.is_empty() { raise Invalid("primitive field has children") }
  }
}

///|
/// Limits are checked before allocating decoded arrays. Input bytes are caller-owned.
pub(all) struct ReadLimits {
  max_rows_per_batch : Int
  max_values_per_batch : Int
  max_fields : Int
  max_batches : Int
  max_metadata_bytes : Int
  max_body_bytes : Int
  max_depth : Int
} derive(Debug)

///|
pub fn ReadLimits::default() -> ReadLimits {
  {
    max_rows_per_batch: 1_000_000,
    max_values_per_batch: 8_000_000,
    max_fields: 1024,
    max_batches: 10_000,
    max_metadata_bytes: 16 * 1024 * 1024,
    max_body_bytes: 256 * 1024 * 1024,
    max_depth: 64,
  }
}

///|
fn ReadLimits::validate(self : ReadLimits) -> Unit raise ArrowError {
  if self.max_rows_per_batch < 0 ||
    self.max_values_per_batch < 0 ||
    self.max_fields < 0 ||
    self.max_batches < 0 ||
    self.max_metadata_bytes < 0 ||
    self.max_body_bytes < 0 || self.max_depth < 0 {
    raise Invalid("reader limits must be nonnegative")
  }
}

///|
/// Materialized IPC data. For batch-at-a-time decoding use StreamReader/FileReader.
pub struct IpcData {
  schema : Schema
  batches : Array[RecordBatch]
} derive(Debug)
