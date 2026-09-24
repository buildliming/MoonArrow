///|
/// A typed value for row-wise construction. None represents an Arrow null.
pub(all) enum Value {
  BooleanValue(Bool)
  Int8Value(Int)
  Int16Value(Int)
  Int32Value(Int)
  Int64Value(Int64)
  UInt8Value(Int)
  UInt16Value(Int)
  UInt32Value(UInt)
  UInt64Value(UInt64)
  Float32Value(Float)
  Float64Value(Double)
  Date32Value(Int)
  Date64Value(Int64)
  TimestampValue(Int64)
  DurationValue(Int64)
  Utf8Value(String)
  BinaryValue(Bytes)
  LargeUtf8Value(String)
  LargeBinaryValue(Bytes)
  FixedBinaryValue(Bytes)
  ListValue(Array[Value?])
  LargeListValue(Array[Value?])
  FixedListValue(Array[Value?])
  StructValue(Array[Value?])
  MapValue(Array[(Value, Value?)])
} derive(Debug)

///|
fn empty_column(field : Field) -> Column raise ArrowError {
  match field.data_type {
    Null => Nulls(0)
    Boolean => Booleans([])
    Int8 => Int8s([])
    Int16 => Int16s([])
    Int32 => Int32s([])
    Int64 => Int64s([])
    UInt8 => UInt8s([])
    UInt16 => UInt16s([])
    UInt32 => UInt32s([])
    UInt64 => UInt64s([])
    Float32 => Float32s([])
    Float64 => Float64s([])
    Date32 => Date32s([])
    Date64 => Date64s([])
    Timestamp(unit, timezone) => Timestamps([], unit, timezone)
    Duration(unit) => Durations([], unit)
    List => Lists([0], [], empty_column(field.children[0]))
    LargeList => LargeLists([0], [], empty_column(field.children[0]))
    Map(sorted) => Maps([0], [], empty_column(field.children[0]), sorted)
    FixedSizeList(size) => FixedLists([], empty_column(field.children[0]), size)
    Struct => Structs([], field.children.map(child => empty_column(child)))
    Dictionary(_, _, _) =>
      raise Unsupported("row builder for dictionary fields")
    Utf8 => Strings([])
    Binary => Binaries([])
    LargeUtf8 => LargeStrings([])
    LargeBinary => LargeBinaries([])
    FixedSizeBinary(width) => FixedBinaries([], width)
  }
}

///|
fn cell_matches(field : Field, value : Value?) -> Bool {
  match value {
    None => field.nullable
    Some(value) => value_matches(field, value)
  }
}

///|
fn value_matches(field : Field, value : Value) -> Bool {
  match (field.data_type, value) {
    (Boolean, BooleanValue(_)) => true
    (Int8, Int8Value(v)) => v >= -128 && v <= 127
    (Int16, Int16Value(v)) => v >= -32768 && v <= 32767
    (Int32, Int32Value(_)) => true
    (Int64, Int64Value(_)) => true
    (UInt8, UInt8Value(v)) => v >= 0 && v <= 255
    (UInt16, UInt16Value(v)) => v >= 0 && v <= 65535
    (UInt32, UInt32Value(_)) => true
    (UInt64, UInt64Value(_)) => true
    (Float32, Float32Value(_)) => true
    (Float64, Float64Value(_)) => true
    (Date32, Date32Value(_)) => true
    (Date64, Date64Value(v)) => v % 86400000L == 0L
    (Timestamp(_, _), TimestampValue(_)) => true
    (Duration(_), DurationValue(_)) => true
    (Utf8, Utf8Value(_)) => true
    (Binary, BinaryValue(_)) => true
    (LargeUtf8, LargeUtf8Value(_)) => true
    (LargeBinary, LargeBinaryValue(_)) => true
    (FixedSizeBinary(width), FixedBinaryValue(value)) => value.length() == width
    (List, ListValue(values)) => {
      if field.children.length() != 1 {
        return false
      }
      for value in values {
        if !cell_matches(field.children[0], value) {
          return false
        }
      }
      true
    }
    (LargeList, LargeListValue(values)) => {
      if field.children.length() != 1 {
        return false
      }
      for value in values {
        if !cell_matches(field.children[0], value) {
          return false
        }
      }
      true
    }
    (FixedSizeList(size), FixedListValue(values)) => {
      if field.children.length() != 1 || values.length() != size {
        return false
      }
      for value in values {
        if !cell_matches(field.children[0], value) {
          return false
        }
      }
      true
    }
    (Struct, StructValue(values)) => {
      if values.length() != field.children.length() {
        return false
      }
      for i in 0..<values.length() {
        if !cell_matches(field.children[i], values[i]) {
          return false
        }
      }
      true
    }
    (Map(_), MapValue(entries)) => {
      if field.children.length() != 1 ||
        field.children[0].children.length() != 2 {
        return false
      }
      let key_field = field.children[0].children[0]
      let value_field = field.children[0].children[1]
      for pair in entries {
        let (key, value) = pair
        if !value_matches(key_field, key) || !cell_matches(value_field, value) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
fn default_cell(field : Field) -> Value? {
  match field.data_type {
    Null => None
    Boolean => Some(BooleanValue(false))
    Int8 => Some(Int8Value(0))
    Int16 => Some(Int16Value(0))
    Int32 => Some(Int32Value(0))
    Int64 => Some(Int64Value(0L))
    UInt8 => Some(UInt8Value(0))
    UInt16 => Some(UInt16Value(0))
    UInt32 => Some(UInt32Value(0U))
    UInt64 => Some(UInt64Value(0UL))
    Float32 => Some(Float32Value(0.0F))
    Float64 => Some(Float64Value(0.0))
    Date32 => Some(Date32Value(0))
    Date64 => Some(Date64Value(0L))
    Timestamp(_, _) => Some(TimestampValue(0L))
    Duration(_) => Some(DurationValue(0L))
    Utf8 => Some(Utf8Value(""))
    Binary => Some(BinaryValue(b""))
    LargeUtf8 => Some(LargeUtf8Value(""))
    LargeBinary => Some(LargeBinaryValue(b""))
    FixedSizeBinary(width) =>
      Some(FixedBinaryValue(Bytes::from_array(Array::make(width, b'\x00'))))
    List => Some(ListValue([]))
    LargeList => Some(LargeListValue([]))
    Map(_) => Some(MapValue([]))
    FixedSizeList(size) =>
      Some(
        FixedListValue(Array::makei(size, _ => default_cell(field.children[0]))),
      )
    Struct =>
      Some(StructValue(field.children.map(child => default_cell(child))))
    Dictionary(_, _, _) => None
  }
}

///|
fn Column::push_value(self : Column, field : Field, value : Value?) -> Column {
  match (self, value) {
    (Nulls(n), _) => Nulls(n + 1)
    (Booleans(a), Some(BooleanValue(v))) => {
      a.push(Some(v))
      self
    }
    (Booleans(a), None) => {
      a.push(None)
      self
    }
    (Int8s(a), Some(Int8Value(v))) => {
      a.push(Some(v))
      self
    }
    (Int8s(a), None) => {
      a.push(None)
      self
    }
    (Int16s(a), Some(Int16Value(v))) => {
      a.push(Some(v))
      self
    }
    (Int16s(a), None) => {
      a.push(None)
      self
    }
    (Int32s(a), Some(Int32Value(v))) => {
      a.push(Some(v))
      self
    }
    (Int32s(a), None) => {
      a.push(None)
      self
    }
    (Int64s(a), Some(Int64Value(v))) => {
      a.push(Some(v))
      self
    }
    (Int64s(a), None) => {
      a.push(None)
      self
    }
    (UInt8s(a), Some(UInt8Value(v))) => {
      a.push(Some(v))
      self
    }
    (UInt8s(a), None) => {
      a.push(None)
      self
    }
    (UInt16s(a), Some(UInt16Value(v))) => {
      a.push(Some(v))
      self
    }
    (UInt16s(a), None) => {
      a.push(None)
      self
    }
    (UInt32s(a), Some(UInt32Value(v))) => {
      a.push(Some(v))
      self
    }
    (UInt32s(a), None) => {
      a.push(None)
      self
    }
    (UInt64s(a), Some(UInt64Value(v))) => {
      a.push(Some(v))
      self
    }
    (UInt64s(a), None) => {
      a.push(None)
      self
    }
    (Float32s(a), Some(Float32Value(v))) => {
      a.push(Some(v))
      self
    }
    (Float32s(a), None) => {
      a.push(None)
      self
    }
    (Float64s(a), Some(Float64Value(v))) => {
      a.push(Some(v))
      self
    }
    (Float64s(a), None) => {
      a.push(None)
      self
    }
    (Date32s(a), Some(Date32Value(v))) => {
      a.push(Some(v))
      self
    }
    (Date32s(a), None) => {
      a.push(None)
      self
    }
    (Date64s(a), Some(Date64Value(v))) => {
      a.push(Some(v))
      self
    }
    (Date64s(a), None) => {
      a.push(None)
      self
    }
    (Timestamps(a, _, _), Some(TimestampValue(v))) => {
      a.push(Some(v))
      self
    }
    (Timestamps(a, _, _), None) => {
      a.push(None)
      self
    }
    (Durations(a, _), Some(DurationValue(v))) => {
      a.push(Some(v))
      self
    }
    (Durations(a, _), None) => {
      a.push(None)
      self
    }
    (Strings(a), Some(Utf8Value(v))) => {
      a.push(Some(v))
      self
    }
    (Strings(a), None) => {
      a.push(None)
      self
    }
    (Binaries(a), Some(BinaryValue(v))) => {
      a.push(Some(v))
      self
    }
    (Binaries(a), None) => {
      a.push(None)
      self
    }
    (LargeStrings(a), Some(LargeUtf8Value(v))) => {
      a.push(Some(v))
      self
    }
    (LargeStrings(a), None) => {
      a.push(None)
      self
    }
    (LargeBinaries(a), Some(LargeBinaryValue(v))) => {
      a.push(Some(v))
      self
    }
    (LargeBinaries(a), None) => {
      a.push(None)
      self
    }
    (FixedBinaries(a, _), Some(FixedBinaryValue(v))) => {
      a.push(Some(v))
      self
    }
    (FixedBinaries(a, _), None) => {
      a.push(None)
      self
    }
    (Lists(offsets, validity, child), Some(ListValue(items))) => {
      let mut updated = child
      for item in items {
        updated = updated.push_value(field.children[0], item)
      }
      validity.push(true)
      offsets.push(updated.length())
      Lists(offsets, validity, updated)
    }
    (Lists(offsets, validity, _), None) => {
      validity.push(false)
      offsets.push(offsets[offsets.length() - 1])
      self
    }
    (LargeLists(offsets, validity, child), Some(LargeListValue(items))) => {
      let mut updated = child
      for item in items {
        updated = updated.push_value(field.children[0], item)
      }
      validity.push(true)
      offsets.push(updated.length())
      LargeLists(offsets, validity, updated)
    }
    (LargeLists(offsets, validity, _), None) => {
      validity.push(false)
      offsets.push(offsets[offsets.length() - 1])
      self
    }
    (Maps(offsets, validity, child, sorted), Some(MapValue(entries))) => {
      let mut updated = child
      for pair in entries {
        let (key, value) = pair
        updated = updated.push_value(
          field.children[0],
          Some(StructValue([Some(key), value])),
        )
      }
      validity.push(true)
      offsets.push(updated.length())
      Maps(offsets, validity, updated, sorted)
    }
    (Maps(offsets, validity, _, _), None) => {
      validity.push(false)
      offsets.push(offsets[offsets.length() - 1])
      self
    }
    (FixedLists(validity, child, size), Some(FixedListValue(items))) => {
      let mut updated = child
      for item in items {
        updated = updated.push_value(field.children[0], item)
      }
      validity.push(true)
      FixedLists(validity, updated, size)
    }
    (FixedLists(validity, child, size), None) => {
      let mut updated = child
      for _ in 0..<size {
        updated = updated.push_value(
          field.children[0],
          default_cell(field.children[0]),
        )
      }
      validity.push(false)
      FixedLists(validity, updated, size)
    }
    (Structs(validity, children), Some(StructValue(items))) => {
      for i in 0..<children.length() {
        children[i] = children[i].push_value(field.children[i], items[i])
      }
      validity.push(true)
      self
    }
    (Structs(validity, children), None) => {
      for i in 0..<children.length() {
        children[i] = children[i].push_value(
          field.children[i],
          default_cell(field.children[i]),
        )
      }
      validity.push(false)
      self
    }
    _ => self // append_row verifies the entire row before mutation
  }
}

///|
/// Row-wise builder for an immutable schema snapshot.
pub struct BatchBuilder {
  priv schema : Schema
  priv columns : Array[Column]
  priv mut rows : Int
}

///|
pub fn BatchBuilder::new(schema : Schema) -> BatchBuilder raise ArrowError {
  validate_schema(schema)
  let owned = copy_schema(schema)
  { schema: owned, columns: owned.fields.map(f => empty_column(f)), rows: 0, }
}

///|
pub fn BatchBuilder::num_rows(self : BatchBuilder) -> Int {
  self.rows
}

///|
/// Append one complete row. A rejected row leaves this builder unchanged.
pub fn BatchBuilder::append_row(
  self : BatchBuilder,
  values : Array[Value?],
) -> Unit raise ArrowError {
  if values.length() != self.schema.fields.length() {
    raise Invalid("builder row width differs from schema")
  }
  if self.rows == 0x7fffffff {
    raise LimitExceeded("builder row count")
  }
  for i in 0..<values.length() {
    let field = self.schema.fields[i]
    match values[i] {
      None =>
        if !field.nullable {
          raise Invalid("null in non-nullable field: " + field.name)
        }
      Some(value) =>
        if !value_matches(field, value) {
          raise Invalid("builder value type or range mismatch: " + field.name)
        }
    }
  }
  for i in 0..<self.columns.length() {
    self.columns[i] = self.columns[i].push_value(
      self.schema.fields[i],
      values[i],
    )
  }
  self.rows += 1
}

///|
/// Return a snapshot. Later appends do not change previously finished batches.
pub fn BatchBuilder::finish(
  self : BatchBuilder,
) -> RecordBatch raise ArrowError {
  let indices = Array::makei(self.rows, i => i)
  RecordBatch::new(
    copy_schema(self.schema),
    self.columns.map(column => column.take_checked(indices)),
    num_rows=self.rows,
  )
}
