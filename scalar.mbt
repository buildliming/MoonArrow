///|
/// Return a logical scalar, resolving dictionary indices and nested child
/// arrays. A returned None represents a null slot at this level.
pub fn Column::get(self : Column, index : Int) -> Value? raise ArrowError {
  if index < 0 || index >= self.length() {
    raise Invalid("column index out of range")
  }
  match self {
    Nulls(_) => None
    Booleans(a) =>
      match a[index] {
        Some(v) => Some(BooleanValue(v))
        None => None
      }
    Int8s(a) =>
      match a[index] {
        Some(v) => Some(Int8Value(v))
        None => None
      }
    Int16s(a) =>
      match a[index] {
        Some(v) => Some(Int16Value(v))
        None => None
      }
    Int32s(a) =>
      match a[index] {
        Some(v) => Some(Int32Value(v))
        None => None
      }
    Int64s(a) =>
      match a[index] {
        Some(v) => Some(Int64Value(v))
        None => None
      }
    UInt8s(a) =>
      match a[index] {
        Some(v) => Some(UInt8Value(v))
        None => None
      }
    UInt16s(a) =>
      match a[index] {
        Some(v) => Some(UInt16Value(v))
        None => None
      }
    UInt32s(a) =>
      match a[index] {
        Some(v) => Some(UInt32Value(v))
        None => None
      }
    UInt64s(a) =>
      match a[index] {
        Some(v) => Some(UInt64Value(v))
        None => None
      }
    Float32s(a) =>
      match a[index] {
        Some(v) => Some(Float32Value(v))
        None => None
      }
    Float64s(a) =>
      match a[index] {
        Some(v) => Some(Float64Value(v))
        None => None
      }
    Date32s(a) =>
      match a[index] {
        Some(v) => Some(Date32Value(v))
        None => None
      }
    Date64s(a) =>
      match a[index] {
        Some(v) => Some(Date64Value(v))
        None => None
      }
    Timestamps(a, _, _) =>
      match a[index] {
        Some(v) => Some(TimestampValue(v))
        None => None
      }
    Durations(a, _) =>
      match a[index] {
        Some(v) => Some(DurationValue(v))
        None => None
      }
    Strings(a) =>
      match a[index] {
        Some(v) => Some(Utf8Value(v))
        None => None
      }
    Binaries(a) =>
      match a[index] {
        Some(v) => Some(BinaryValue(v))
        None => None
      }
    LargeStrings(a) =>
      match a[index] {
        Some(v) => Some(LargeUtf8Value(v))
        None => None
      }
    LargeBinaries(a) =>
      match a[index] {
        Some(v) => Some(LargeBinaryValue(v))
        None => None
      }
    FixedBinaries(a, _) =>
      match a[index] {
        Some(v) => Some(FixedBinaryValue(v))
        None => None
      }
    Lists(offsets, valid, child) => {
      if !valid[index] {
        return None
      }
      let result = []
      for i in offsets[index]..<offsets[index + 1] {
        result.push(child.get(i))
      }
      Some(ListValue(result))
    }
    LargeLists(offsets, valid, child) => {
      if !valid[index] {
        return None
      }
      let result = []
      for i in offsets[index]..<offsets[index + 1] {
        result.push(child.get(i))
      }
      Some(LargeListValue(result))
    }
    FixedLists(valid, child, size) => {
      if !valid[index] {
        return None
      }
      let result = []
      for i in 0..<size {
        result.push(child.get(index * size + i))
      }
      Some(FixedListValue(result))
    }
    Structs(valid, children) => {
      if !valid[index] {
        return None
      }
      let result = []
      for child in children {
        result.push(child.get(index))
      }
      Some(StructValue(result))
    }
    Maps(offsets, valid, child, _) => {
      if !valid[index] {
        return None
      }
      guard child is Structs(_, children) && children.length() == 2 else {
        raise Invalid("Map child is not a two-field Struct")
      }
      let pairs = []
      for i in offsets[index]..<offsets[index + 1] {
        guard children[0].get(i) is Some(key) else {
          raise Invalid("null Map key")
        }
        pairs.push((key, children[1].get(i)))
      }
      Some(MapValue(pairs))
    }
    Dictionaries(indices, values, _, _) =>
      match indices[index] {
        None => None
        Some(i) => values.get(i)
      }
  }
}

///|
pub fn RecordBatch::get_row(
  self : RecordBatch,
  index : Int,
) -> Array[Value?] raise ArrowError {
  self.validate()
  if index < 0 || index >= self.num_rows {
    raise Invalid("row index out of range")
  }
  self.row_unchecked(index)
}

///|
fn RecordBatch::row_unchecked(
  self : RecordBatch,
  index : Int,
) -> Array[Value?] raise ArrowError {
  self.columns.map(column => column.get(index))
}

///|
pub fn Table::get_row(
  self : Table,
  index : Int,
) -> Array[Value?] raise ArrowError {
  if index < 0 || index >= self.num_rows() {
    raise Invalid("table row index out of range")
  }
  let mut remaining = index
  for i in 0..<self.num_batches() {
    let batch = self.get_batch(i)
    if remaining < batch.num_rows {
      return batch.get_row(remaining)
    }
    remaining -= batch.num_rows
  }
  raise Invalid("table row index out of range")
}

///|
/// Append a validated batch to a row builder. Dictionary fields are currently
/// unsupported by this builder and are rejected before any row is appended.
pub fn BatchBuilder::append_batch(
  self : BatchBuilder,
  batch : RecordBatch,
) -> Unit raise ArrowError {
  batch.validate()
  if batch.schema != self.schema {
    raise Invalid("builder batch schema mismatch")
  }
  if batch.num_rows > 0x7fffffff - self.num_rows() {
    raise LimitExceeded("builder row count")
  }
  for field in batch.schema.fields {
    if field.data_type is Dictionary(_, _, _) {
      raise Unsupported("row builder for dictionary fields")
    }
  }
  for i in 0..<batch.num_rows {
    self.append_row(batch.row_unchecked(i))
  }
}
