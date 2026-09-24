///|
/// Copy selected column slots in arbitrary order. Duplicate indices are kept.
pub fn Column::take(
  self : Column,
  indices : Array[Int],
) -> Column raise ArrowError {
  for index in indices {
    if index < 0 || index >= self.length() {
      raise Invalid("column index out of range")
    }
  }
  self.take_checked(indices)
}

///|
pub fn Column::slice(
  self : Column,
  start : Int,
  length : Int,
) -> Column raise ArrowError {
  if start < 0 ||
    length < 0 ||
    start > self.length() ||
    length > self.length() - start {
    raise Invalid("column slice outside length")
  }
  self.take_checked(Array::makei(length, i => start + i))
}

///|
/// Split a batch into matching and nonmatching rows, preserving row order in
/// both results. Null values use the predicate's documented semantics.
pub fn RecordBatch::partition_where(
  self : RecordBatch,
  predicate : Predicate,
) -> (RecordBatch, RecordBatch) raise ArrowError {
  self.validate()
  predicate.check(self.schema)
  let accepted = []
  let rejected = []
  for i in 0..<self.num_rows {
    if predicate.evaluate(self, i) {
      accepted.push(i)
    } else {
      rejected.push(i)
    }
  }
  (self.take(accepted), self.take(rejected))
}

///|
pub fn Table::partition_where(
  self : Table,
  predicate : Predicate,
) -> (Table, Table) raise ArrowError {
  predicate.check(self.schema)
  let accepted = []
  let rejected = []
  for batch in self.batches {
    let (yes, no) = batch.partition_where(predicate)
    accepted.push(yes)
    rejected.push(no)
  }
  (Table::new(self.schema, accepted), Table::new(self.schema, rejected))
}

///|
pub fn RecordBatch::head(
  self : RecordBatch,
  count : Int,
) -> RecordBatch raise ArrowError {
  if count < 0 {
    raise Invalid("negative head count")
  }
  self.slice(0, if count < self.num_rows { count } else { self.num_rows })
}

///|
pub fn RecordBatch::tail(
  self : RecordBatch,
  count : Int,
) -> RecordBatch raise ArrowError {
  if count < 0 {
    raise Invalid("negative tail count")
  }
  let size = if count < self.num_rows { count } else { self.num_rows }
  self.slice(self.num_rows - size, size)
}

///|
pub fn Table::head(self : Table, count : Int) -> Table raise ArrowError {
  if count < 0 {
    raise Invalid("negative head count")
  }
  self.slice_rows(
    0,
    if count < self.num_rows() {
      count
    } else {
      self.num_rows()
    },
  )
}

///|
pub fn Table::tail(self : Table, count : Int) -> Table raise ArrowError {
  if count < 0 {
    raise Invalid("negative tail count")
  }
  let size = if count < self.num_rows() { count } else { self.num_rows() }
  self.slice_rows(self.num_rows() - size, size)
}

///|
/// Select global table rows in arbitrary order. Duplicate indices are kept.
/// The output is a Table because source rows may come from separate batches.
pub fn Table::take_rows(
  self : Table,
  indices : Array[Int],
) -> Table raise ArrowError {
  let selected = []
  for index in indices {
    if index < 0 || index >= self.num_rows() {
      raise Invalid("table row index out of range")
    }
    let mut row_index = index
    for batch in self.batches {
      if row_index < batch.num_rows {
        selected.push(batch.take([row_index]))
        break
      }
      row_index -= batch.num_rows
    }
  }
  Table::new(self.schema, selected)
}
