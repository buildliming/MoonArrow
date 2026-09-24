///|
/// A small, typed predicate for batch and table filtering. Equality uses
/// floating-point bit patterns, so -0.0 differs from +0.0 and equal NaN
/// payloads compare equal. Null values never satisfy Eq or Ne.
pub(all) enum Predicate {
  Eq(Int, Value)
  Ne(Int, Value)
  IsNull(Int)
  IsNotNull(Int)
  And(Predicate, Predicate)
  Or(Predicate, Predicate)
  Not(Predicate)
} derive(Debug)

///|
fn predicate_value_supported(data_type : DataType) -> Bool {
  match data_type {
    List | LargeList | FixedSizeList(_) | Struct | Dictionary(_, _, _) | Null =>
      false
    _ => true
  }
}

///|
fn Predicate::check(self : Predicate, schema : Schema) -> Unit raise ArrowError {
  match self {
    Eq(index, value) | Ne(index, value) => {
      if index < 0 || index >= schema.fields.length() {
        raise Invalid("predicate column index out of range")
      }
      let field = schema.fields[index]
      if !predicate_value_supported(field.data_type) ||
        !value_matches(field, value) {
        raise Unsupported("predicate value incompatible with column")
      }
    }
    IsNull(index) | IsNotNull(index) =>
      if index < 0 || index >= schema.fields.length() {
        raise Invalid("predicate column index out of range")
      }
    And(a, b) | Or(a, b) => {
      a.check(schema)
      b.check(schema)
    }
    Not(a) => a.check(schema)
  }
}

///|
fn Column::equals_value(self : Column, row : Int, value : Value) -> Bool {
  match (self, value) {
    (Booleans(a), BooleanValue(x)) => a[row] == Some(x)
    (Int8s(a), Int8Value(x)) => a[row] == Some(x)
    (Int16s(a), Int16Value(x)) => a[row] == Some(x)
    (Int32s(a), Int32Value(x)) => a[row] == Some(x)
    (Int64s(a), Int64Value(x)) => a[row] == Some(x)
    (UInt8s(a), UInt8Value(x)) => a[row] == Some(x)
    (UInt16s(a), UInt16Value(x)) => a[row] == Some(x)
    (UInt32s(a), UInt32Value(x)) => a[row] == Some(x)
    (UInt64s(a), UInt64Value(x)) => a[row] == Some(x)
    (Float32s(a), Float32Value(x)) =>
      match a[row] {
        Some(v) => v.reinterpret_as_int() == x.reinterpret_as_int()
        None => false
      }
    (Float64s(a), Float64Value(x)) =>
      match a[row] {
        Some(v) => v.reinterpret_as_int64() == x.reinterpret_as_int64()
        None => false
      }
    (Date32s(a), Date32Value(x)) => a[row] == Some(x)
    (Date64s(a), Date64Value(x)) => a[row] == Some(x)
    (Timestamps(a, _, _), TimestampValue(x)) => a[row] == Some(x)
    (Durations(a, _), DurationValue(x)) => a[row] == Some(x)
    (Strings(a), Utf8Value(x)) => a[row] == Some(x)
    (Binaries(a), BinaryValue(x)) => a[row] == Some(x)
    (LargeStrings(a), LargeUtf8Value(x)) => a[row] == Some(x)
    (LargeBinaries(a), LargeBinaryValue(x)) => a[row] == Some(x)
    (FixedBinaries(a, _), FixedBinaryValue(x)) => a[row] == Some(x)
    _ => false
  }
}

///|
fn Predicate::evaluate(
  self : Predicate,
  batch : RecordBatch,
  row : Int,
) -> Bool {
  match self {
    Eq(index, value) => batch.columns[index].equals_value(row, value)
    Ne(index, value) =>
      batch.columns[index].valid_at(row) &&
      !batch.columns[index].equals_value(row, value)
    IsNull(index) => !batch.columns[index].valid_at(row)
    IsNotNull(index) => batch.columns[index].valid_at(row)
    And(a, b) => a.evaluate(batch, row) && b.evaluate(batch, row)
    Or(a, b) => a.evaluate(batch, row) || b.evaluate(batch, row)
    Not(a) => !a.evaluate(batch, row)
  }
}

///|
/// Filter rows using a checked expression, preserving schema and row order.
pub fn RecordBatch::filter_where(
  self : RecordBatch,
  predicate : Predicate,
) -> RecordBatch raise ArrowError {
  self.validate()
  predicate.check(self.schema)
  let indices = []
  for i in 0..<self.num_rows {
    if predicate.evaluate(self, i) {
      indices.push(i)
    }
  }
  self.take(indices)
}

///|
pub fn Table::filter_where(
  self : Table,
  predicate : Predicate,
) -> Table raise ArrowError {
  predicate.check(self.schema)
  let batches = []
  for i in 0..<self.num_batches() {
    batches.push(self.get_batch(i).filter_where(predicate))
  }
  Table::new(self.schema, batches)
}
