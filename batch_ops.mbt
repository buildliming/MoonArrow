///|
fn copy_field(field : Field) -> Field {
  Field::new(field.name, field.data_type, nullable=field.nullable,
    metadata=field.metadata.map(kv => kv),
    children=field.children.map(child => copy_field(child)))
}

///|
fn copy_schema(schema : Schema) -> Schema {
  Schema::new(
    schema.fields.map(field => copy_field(field)),
    metadata=schema.metadata.map(kv => kv),
  )
}

///|
fn[T] take_values(values : Array[T], indices : Array[Int]) -> Array[T] {
  Array::makei(indices.length(), i => values[indices[i]])
}

///|
fn[T] append_values(left : Array[T], right : Array[T]) -> Array[T] {
  let result = []
  for value in left { result.push(value) }
  for value in right { result.push(value) }
  result
}

///|
fn Column::take_checked(self : Column, indices : Array[Int]) -> Column {
  match self {
    Nulls(_) => Nulls(indices.length())
    Booleans(a) => Booleans(take_values(a, indices))
    Int8s(a) => Int8s(take_values(a, indices))
    Int16s(a) => Int16s(take_values(a, indices))
    Int32s(a) => Int32s(take_values(a, indices))
    Int64s(a) => Int64s(take_values(a, indices))
    UInt8s(a) => UInt8s(take_values(a, indices))
    UInt16s(a) => UInt16s(take_values(a, indices))
    UInt32s(a) => UInt32s(take_values(a, indices))
    UInt64s(a) => UInt64s(take_values(a, indices))
    Float32s(a) => Float32s(take_values(a, indices))
    Float64s(a) => Float64s(take_values(a, indices))
    Date32s(a) => Date32s(take_values(a, indices))
    Date64s(a) => Date64s(take_values(a, indices))
    Timestamps(a, unit, timezone) => Timestamps(take_values(a, indices), unit, timezone)
    Durations(a, unit) => Durations(take_values(a, indices), unit)
    Lists(offsets, validity, child) => {
      let child_indices = []
      let selected_offsets = [0]
      for index in indices {
        for j in offsets[index]..<offsets[index + 1] { child_indices.push(j) }
        selected_offsets.push(child_indices.length())
      }
      Lists(selected_offsets, take_values(validity, indices), child.take_checked(child_indices))
    }
    Structs(validity, children) => Structs(take_values(validity, indices),
      children.map(child => child.take_checked(indices)))
    Dictionaries(indices_array, values, id, ordered) => Dictionaries(
      take_values(indices_array, indices),
      values.take_checked(Array::makei(values.length(), i => i)), id, ordered)
    Strings(a) => Strings(take_values(a, indices))
    Binaries(a) => Binaries(take_values(a, indices))
  }
}

///|
fn Column::append_checked(self : Column, other : Column) -> Column raise ArrowError {
  match (self, other) {
    (Nulls(a), Nulls(b)) => Nulls(a + b)
    (Booleans(a), Booleans(b)) => Booleans(append_values(a, b))
    (Int8s(a), Int8s(b)) => Int8s(append_values(a, b))
    (Int16s(a), Int16s(b)) => Int16s(append_values(a, b))
    (Int32s(a), Int32s(b)) => Int32s(append_values(a, b))
    (Int64s(a), Int64s(b)) => Int64s(append_values(a, b))
    (UInt8s(a), UInt8s(b)) => UInt8s(append_values(a, b))
    (UInt16s(a), UInt16s(b)) => UInt16s(append_values(a, b))
    (UInt32s(a), UInt32s(b)) => UInt32s(append_values(a, b))
    (UInt64s(a), UInt64s(b)) => UInt64s(append_values(a, b))
    (Float32s(a), Float32s(b)) => Float32s(append_values(a, b))
    (Float64s(a), Float64s(b)) => Float64s(append_values(a, b))
    (Date32s(a), Date32s(b)) => Date32s(append_values(a, b))
    (Date64s(a), Date64s(b)) => Date64s(append_values(a, b))
    (Timestamps(a, u, z), Timestamps(b, _, _)) => Timestamps(append_values(a, b), u, z)
    (Durations(a, u), Durations(b, _)) => Durations(append_values(a, b), u)
    (Lists(a, av, ac), Lists(b, bv, bc)) => {
      let left = Lists(a, av, ac).take_checked(Array::makei(av.length(), i => i))
      let right = Lists(b, bv, bc).take_checked(Array::makei(bv.length(), i => i))
      guard left is Lists(la, lv, lc) && right is Lists(rb, rv, rc) else {
        raise Invalid("internal List concat")
      }
      let offsets = la.map(x => x)
      let base = la[la.length() - 1]
      for i in 1..<rb.length() { offsets.push(base + rb[i]) }
      Lists(offsets, append_values(lv, rv), lc.append_checked(rc))
    }
    (Structs(av, ac), Structs(bv, bc)) => {
      let children = []
      for i in 0..<ac.length() { children.push(ac[i].append_checked(bc[i])) }
      Structs(append_values(av, bv), children)
    }
    (Dictionaries(a, av, id, ordered), Dictionaries(b, bv, _, _)) => {
      if dictionary_equal(av, bv) {
        Dictionaries(append_values(a, b), av, id, ordered)
      } else {
        let base = av.length()
        let shifted = b.map(index => match index {
          Some(i) => Some(i + base)
          None => None
        })
        Dictionaries(append_values(a, shifted), av.append_checked(bv), id, ordered)
      }
    }
    (Strings(a), Strings(b)) => Strings(append_values(a, b))
    (Binaries(a), Binaries(b)) => Binaries(append_values(a, b))
    _ => raise Invalid("column type mismatch in concat")
  }
}

///|
/// Select fields by index. Duplicate indices are kept in the requested order.
/// The result has fresh mutable column, field and metadata arrays.
pub fn RecordBatch::project(self : RecordBatch, indices : Array[Int]) -> RecordBatch raise ArrowError {
  self.validate()
  let fields = []
  let columns = []
  for index in indices {
    if index < 0 || index >= self.columns.length() {
      raise Invalid("project field index out of range")
    }
    let field = self.schema.fields[index]
    fields.push(copy_field(field))
    columns.push(self.columns[index].take_checked(Array::makei(self.num_rows, i => i)))
  }
  RecordBatch::new(Schema::new(fields, metadata=self.schema.metadata.map(kv => kv)),
    columns, num_rows=self.num_rows)
}

///|
/// Take rows in arbitrary order. Repeated indices are preserved.
pub fn RecordBatch::take(self : RecordBatch, indices : Array[Int]) -> RecordBatch raise ArrowError {
  self.validate()
  for index in indices {
    if index < 0 || index >= self.num_rows {
      raise Invalid("take row index out of range")
    }
  }
  RecordBatch::new(copy_schema(self.schema),
    self.columns.map(column => column.take_checked(indices)),
    num_rows=indices.length())
}

///|
/// Copy a contiguous range of rows. A zero-length slice at the end is valid.
pub fn RecordBatch::slice(self : RecordBatch, start : Int, length : Int) -> RecordBatch raise ArrowError {
  self.validate()
  if start < 0 || length < 0 || start > self.num_rows || length > self.num_rows - start {
    raise Invalid("slice outside batch")
  }
  self.take(Array::makei(length, i => start + i))
}

///|
/// Keep rows whose mask is Some(true). None is treated as false.
pub fn RecordBatch::filter(self : RecordBatch, mask : Array[Bool?]) -> RecordBatch raise ArrowError {
  self.validate()
  if mask.length() != self.num_rows { raise Invalid("filter mask length mismatch") }
  let indices = []
  for i in 0..<mask.length() {
    if mask[i] == Some(true) { indices.push(i) }
  }
  self.take(indices)
}

///|
/// Append batches with exactly equal schemas. The result owns new arrays.
pub fn RecordBatch::concat(self : RecordBatch, others : Array[RecordBatch]) -> RecordBatch raise ArrowError {
  self.validate()
  let columns = self.columns.map(column =>
    column.take_checked(Array::makei(self.num_rows, i => i)))
  let mut rows = self.num_rows
  for batch in others {
    batch.validate()
    if batch.schema != self.schema { raise Invalid("concat schema mismatch") }
    if batch.num_rows > 0x7fffffff - rows { raise LimitExceeded("concat row count") }
    for i in 0..<columns.length() {
      columns[i] = columns[i].append_checked(batch.columns[i])
    }
    rows += batch.num_rows
  }
  RecordBatch::new(copy_schema(self.schema), columns, num_rows=rows)
}
