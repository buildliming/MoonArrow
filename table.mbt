///|
/// A validated collection of record batches with one shared schema. Tables
/// own snapshots of their input batches; mutating a caller array after new or
/// append cannot change the stored rows.
pub struct Table {
  schema : Schema
  priv batches : Array[RecordBatch]
  priv mut row_count : Int
}

///|
pub fn Table::new(
  schema : Schema,
  batches : Array[RecordBatch],
) -> Table raise ArrowError {
  validate_schema(schema)
  let owned_schema = copy_schema(schema)
  let owned_batches = []
  let mut rows = 0
  for batch in batches {
    batch.validate()
    if batch.schema != schema {
      raise Invalid("table batch schema mismatch")
    }
    if batch.num_rows > 0x7fffffff - rows {
      raise LimitExceeded("table row count")
    }
    rows += batch.num_rows
    owned_batches.push(batch.take(Array::makei(batch.num_rows, i => i)))
  }
  { schema: owned_schema, batches: owned_batches, row_count: rows, }
}

///|
pub fn Table::from_stream(
  bytes : Bytes,
  limits? : ReadLimits = ReadLimits::default(),
) -> Table raise ArrowError {
  let data = read_stream(bytes, limits~)
  Table::new(data.schema, data.batches)
}

///|
pub fn Table::from_file(
  bytes : Bytes,
  limits? : ReadLimits = ReadLimits::default(),
) -> Table raise ArrowError {
  let data = read_file(bytes, limits~)
  Table::new(data.schema, data.batches)
}

///|
/// Convert a materialized IPC result into an owned Table.
pub fn IpcData::to_table(self : IpcData) -> Table raise ArrowError {
  Table::new(self.schema, self.batches)
}

///|
/// Return independent batch snapshots for callers using the original IPC API.
pub fn Table::to_ipc_data(self : Table) -> IpcData raise ArrowError {
  let batches = []
  for i in 0..<self.num_batches() {
    batches.push(self.get_batch(i))
  }
  IpcData::{ schema: copy_schema(self.schema), batches, }
}

///|
pub fn Table::num_rows(self : Table) -> Int {
  self.row_count
}

///|
pub fn Table::is_empty(self : Table) -> Bool {
  self.row_count == 0
}

///|
pub fn Table::num_batches(self : Table) -> Int {
  self.batches.length()
}

///|
pub fn Table::get_batch(
  self : Table,
  index : Int,
) -> RecordBatch raise ArrowError {
  if index < 0 || index >= self.batches.length() {
    raise Invalid("table batch index out of range")
  }
  let batch = self.batches[index]
  batch.take(Array::makei(batch.num_rows, i => i))
}

///|
/// Append one batch after validating the whole batch. The stored rows are
/// detached from the caller's mutable arrays.
pub fn Table::append(
  self : Table,
  batch : RecordBatch,
) -> Unit raise ArrowError {
  batch.validate()
  if batch.schema != self.schema {
    raise Invalid("table batch schema mismatch")
  }
  if batch.num_rows > 0x7fffffff - self.row_count {
    raise LimitExceeded("table row count")
  }
  let owned = batch.take(Array::makei(batch.num_rows, i => i))
  self.batches.push(owned)
  self.row_count += batch.num_rows
}

///|
/// Select columns in every batch, preserving batch boundaries and metadata.
pub fn Table::project(
  self : Table,
  indices : Array[Int],
) -> Table raise ArrowError {
  if self.batches.is_empty() {
    let fields = []
    for index in indices {
      if index < 0 || index >= self.schema.fields.length() {
        raise Invalid("project field index out of range")
      }
      fields.push(copy_field(self.schema.fields[index]))
    }
    return Table::new(
      Schema::new(fields, metadata=self.schema.metadata.map(kv => kv)),
      [],
    )
  }
  let projected = self.batches.map(batch => batch.project(indices))
  Table::new(projected[0].schema, projected)
}

///|
/// Return a range of global table rows. A range may cross batch boundaries.
pub fn Table::slice_rows(
  self : Table,
  start : Int,
  length : Int,
) -> Table raise ArrowError {
  if start < 0 ||
    length < 0 ||
    start > self.row_count ||
    length > self.row_count - start {
    raise Invalid("table slice outside rows")
  }
  let selected = []
  let stop = start + length
  let mut position = 0
  for batch in self.batches {
    let batch_end = position + batch.num_rows
    let from = if start > position { start } else { position }
    let to = if stop < batch_end { stop } else { batch_end }
    if from < to {
      selected.push(batch.slice(from - position, to - from))
    }
    position = batch_end
  }
  Table::new(self.schema, selected)
}

///|
/// Apply one nullable row mask over all batches. Null mask entries are false.
pub fn Table::filter(
  self : Table,
  mask : Array[Bool?],
) -> Table raise ArrowError {
  if mask.length() != self.row_count {
    raise Invalid("table mask length mismatch")
  }
  let result = []
  let mut position = 0
  for batch in self.batches {
    let part = Array::makei(batch.num_rows, i => mask[position + i])
    result.push(batch.filter(part))
    position += batch.num_rows
  }
  Table::new(self.schema, result)
}

///|
/// Concatenate tables with exactly equal schemas and retain batch boundaries.
pub fn Table::concat(self : Table, other : Table) -> Table raise ArrowError {
  if self.schema != other.schema {
    raise Invalid("table schema mismatch")
  }
  if other.row_count > 0x7fffffff - self.row_count {
    raise LimitExceeded("table row count")
  }
  Table::new(self.schema, append_values(self.batches, other.batches))
}

///|
/// Rechunk batches to at most max_rows rows. This is useful for controlling
/// downstream IPC message size, especially when source batches are uneven.
pub fn Table::rechunk(self : Table, max_rows : Int) -> Table raise ArrowError {
  if max_rows <= 0 {
    raise Invalid("max_rows must be positive")
  }
  let result = []
  let mut pending : RecordBatch? = None
  for batch in self.batches {
    let mut position = 0
    while position < batch.num_rows {
      let used = match pending {
        Some(p) => p.num_rows
        None => 0
      }
      let capacity = max_rows - used
      let remaining = batch.num_rows - position
      let amount = if remaining < capacity { remaining } else { capacity }
      let part = batch.slice(position, amount)
      pending = match pending {
        None => Some(part)
        Some(p) => Some(p.concat([part]))
      }
      position += amount
      if pending is Some(full) {
        if full.num_rows == max_rows {
          result.push(full)
          pending = None
        }
      }
    }
  }
  if pending is Some(last) {
    result.push(last)
  }
  Table::new(self.schema, result)
}

///|
pub fn Table::to_stream(self : Table) -> Bytes raise ArrowError {
  write_stream(self.schema, self.batches)
}

///|
pub fn Table::to_file(self : Table) -> Bytes raise ArrowError {
  write_file(self.schema, self.batches)
}
