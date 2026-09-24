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
} derive(Debug)

///|
fn empty_column(data_type : DataType) -> Column raise ArrowError {
  match data_type {
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
    List | Struct | Dictionary(_, _, _) => raise Unsupported("row builder for nested or dictionary fields")
    Utf8 => Strings([])
    Binary => Binaries([])
  }
}

///|
fn value_matches(data_type : DataType, value : Value) -> Bool {
  match (data_type, value) {
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
    _ => false
  }
}

///|
fn Column::push_value(self : Column, value : Value?) -> Column {
  match (self, value) {
    (Nulls(n), _) => Nulls(n + 1)
    (Booleans(a), Some(BooleanValue(v))) => { a.push(Some(v)); self }
    (Booleans(a), None) => { a.push(None); self }
    (Int8s(a), Some(Int8Value(v))) => { a.push(Some(v)); self }
    (Int8s(a), None) => { a.push(None); self }
    (Int16s(a), Some(Int16Value(v))) => { a.push(Some(v)); self }
    (Int16s(a), None) => { a.push(None); self }
    (Int32s(a), Some(Int32Value(v))) => { a.push(Some(v)); self }
    (Int32s(a), None) => { a.push(None); self }
    (Int64s(a), Some(Int64Value(v))) => { a.push(Some(v)); self }
    (Int64s(a), None) => { a.push(None); self }
    (UInt8s(a), Some(UInt8Value(v))) => { a.push(Some(v)); self }
    (UInt8s(a), None) => { a.push(None); self }
    (UInt16s(a), Some(UInt16Value(v))) => { a.push(Some(v)); self }
    (UInt16s(a), None) => { a.push(None); self }
    (UInt32s(a), Some(UInt32Value(v))) => { a.push(Some(v)); self }
    (UInt32s(a), None) => { a.push(None); self }
    (UInt64s(a), Some(UInt64Value(v))) => { a.push(Some(v)); self }
    (UInt64s(a), None) => { a.push(None); self }
    (Float32s(a), Some(Float32Value(v))) => { a.push(Some(v)); self }
    (Float32s(a), None) => { a.push(None); self }
    (Float64s(a), Some(Float64Value(v))) => { a.push(Some(v)); self }
    (Float64s(a), None) => { a.push(None); self }
    (Date32s(a), Some(Date32Value(v))) => { a.push(Some(v)); self }
    (Date32s(a), None) => { a.push(None); self }
    (Date64s(a), Some(Date64Value(v))) => { a.push(Some(v)); self }
    (Date64s(a), None) => { a.push(None); self }
    (Timestamps(a, _, _), Some(TimestampValue(v))) => { a.push(Some(v)); self }
    (Timestamps(a, _, _), None) => { a.push(None); self }
    (Durations(a, _), Some(DurationValue(v))) => { a.push(Some(v)); self }
    (Durations(a, _), None) => { a.push(None); self }
    (Strings(a), Some(Utf8Value(v))) => { a.push(Some(v)); self }
    (Strings(a), None) => { a.push(None); self }
    (Binaries(a), Some(BinaryValue(v))) => { a.push(Some(v)); self }
    (Binaries(a), None) => { a.push(None); self }
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
  let owned = copy_schema(schema)
  { schema: owned, columns: owned.fields.map(f => empty_column(f.data_type)), rows: 0, }
}

///|
pub fn BatchBuilder::num_rows(self : BatchBuilder) -> Int { self.rows }

///|
/// Append one complete row. A rejected row leaves this builder unchanged.
pub fn BatchBuilder::append_row(self : BatchBuilder, values : Array[Value?]) -> Unit raise ArrowError {
  if values.length() != self.schema.fields.length() {
    raise Invalid("builder row width differs from schema")
  }
  if self.rows == 0x7fffffff { raise LimitExceeded("builder row count") }
  for i in 0..<values.length() {
    let field = self.schema.fields[i]
    match values[i] {
      None => if !field.nullable {
        raise Invalid("null in non-nullable field: " + field.name)
      }
      Some(value) => if !value_matches(field.data_type, value) {
        raise Invalid("builder value type or range mismatch: " + field.name)
      }
    }
  }
  for i in 0..<self.columns.length() {
    self.columns[i] = self.columns[i].push_value(values[i])
  }
  self.rows += 1
}

///|
/// Return a snapshot. Later appends do not change previously finished batches.
pub fn BatchBuilder::finish(self : BatchBuilder) -> RecordBatch raise ArrowError {
  let indices = Array::makei(self.rows, i => i)
  RecordBatch::new(copy_schema(self.schema),
    self.columns.map(column => column.take_checked(indices)), num_rows=self.rows)
}
