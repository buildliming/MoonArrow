///|
/// Physical value range for a column. Float ranges ignore NaN values; all
/// null slots are excluded. Byte lengths count encoded UTF-8 bytes for text.
pub(all) enum ColumnRange {
  NoRange
  IntRange(Int, Int)
  Int64Range(Int64, Int64)
  UIntRange(UInt, UInt)
  UInt64Range(UInt64, UInt64)
  Float32Range(Float, Float)
  Float64Range(Double, Double)
  ByteLengthRange(Int, Int, Int64)
  BooleanCounts(Int, Int)
} derive(Debug)

///|
pub(all) struct ColumnSummary {
  length : Int
  null_count : Int
  range : ColumnRange
} derive(Debug)

///|
fn summarize_int(values : Array[Int?]) -> ColumnRange {
  let mut low : Int? = None
  let mut high : Int? = None
  for value in values {
    if value is Some(x) {
      low = Some(if low is Some(v) { if x < v { x } else { v } } else { x })
      high = Some(if high is Some(v) { if x > v { x } else { v } } else { x })
    }
  }
  match (low, high) {
    (Some(a), Some(b)) => IntRange(a, b)
    _ => NoRange
  }
}

///|
fn summarize_int64(values : Array[Int64?]) -> ColumnRange {
  let mut low : Int64? = None
  let mut high : Int64? = None
  for value in values {
    if value is Some(x) {
      low = Some(if low is Some(v) { if x < v { x } else { v } } else { x })
      high = Some(if high is Some(v) { if x > v { x } else { v } } else { x })
    }
  }
  match (low, high) {
    (Some(a), Some(b)) => Int64Range(a, b)
    _ => NoRange
  }
}

///|
fn summarize_uint(values : Array[UInt?]) -> ColumnRange {
  let mut low : UInt? = None
  let mut high : UInt? = None
  for value in values {
    if value is Some(x) {
      low = Some(if low is Some(v) { if x < v { x } else { v } } else { x })
      high = Some(if high is Some(v) { if x > v { x } else { v } } else { x })
    }
  }
  match (low, high) {
    (Some(a), Some(b)) => UIntRange(a, b)
    _ => NoRange
  }
}

///|
fn summarize_uint64(values : Array[UInt64?]) -> ColumnRange {
  let mut low : UInt64? = None
  let mut high : UInt64? = None
  for value in values {
    if value is Some(x) {
      low = Some(if low is Some(v) { if x < v { x } else { v } } else { x })
      high = Some(if high is Some(v) { if x > v { x } else { v } } else { x })
    }
  }
  match (low, high) {
    (Some(a), Some(b)) => UInt64Range(a, b)
    _ => NoRange
  }
}

///|
fn summarize_float(values : Array[Float?]) -> ColumnRange {
  let mut low : Float? = None
  let mut high : Float? = None
  for value in values {
    if value is Some(x) && x == x {
      low = Some(if low is Some(v) { if x < v { x } else { v } } else { x })
      high = Some(if high is Some(v) { if x > v { x } else { v } } else { x })
    }
  }
  match (low, high) {
    (Some(a), Some(b)) => Float32Range(a, b)
    _ => NoRange
  }
}

///|
fn summarize_double(values : Array[Double?]) -> ColumnRange {
  let mut low : Double? = None
  let mut high : Double? = None
  for value in values {
    if value is Some(x) && x == x {
      low = Some(if low is Some(v) { if x < v { x } else { v } } else { x })
      high = Some(if high is Some(v) { if x > v { x } else { v } } else { x })
    }
  }
  match (low, high) {
    (Some(a), Some(b)) => Float64Range(a, b)
    _ => NoRange
  }
}

///|
fn summarize_lengths(values : Array[Bytes?]) -> ColumnRange {
  let mut low = 0x7fffffff
  let mut high = 0
  let mut total = 0L
  for value in values {
    if value is Some(bytes) {
      let length = bytes.length()
      if length < low {
        low = length
      }
      if length > high {
        high = length
      }
      total += length.to_int64()
    }
  }
  if low == 0x7fffffff {
    NoRange
  } else {
    ByteLengthRange(low, high, total)
  }
}

///|
fn summarize_offsets(offsets : Array[Int], valid : Array[Bool]) -> ColumnRange {
  let mut low = 0x7fffffff
  let mut high = 0
  let mut total = 0L
  for i in 0..<valid.length() {
    if valid[i] {
      let length = offsets[i + 1] - offsets[i]
      if length < low {
        low = length
      }
      if length > high {
        high = length
      }
      total += length.to_int64()
    }
  }
  if low == 0x7fffffff {
    NoRange
  } else {
    ByteLengthRange(low, high, total)
  }
}

///|
pub fn Column::summary(self : Column) -> ColumnSummary {
  let range = match self {
    Nulls(_) => NoRange
    Booleans(values) => {
      let mut yes = 0
      let mut no = 0
      for value in values {
        match value {
          Some(true) => yes += 1
          Some(false) => no += 1
          None => ()
        }
      }
      BooleanCounts(yes, no)
    }
    Int8s(a) | Int16s(a) | Int32s(a) | UInt8s(a) | UInt16s(a) | Date32s(a) =>
      summarize_int(a)
    Int64s(a) | Date64s(a) | Timestamps(a, _, _) | Durations(a, _) =>
      summarize_int64(a)
    UInt32s(a) => summarize_uint(a)
    UInt64s(a) => summarize_uint64(a)
    Float32s(a) => summarize_float(a)
    Float64s(a) => summarize_double(a)
    Strings(values) | LargeStrings(values) =>
      summarize_lengths(
        values.map(value => {
          match value {
            Some(text) => Some(@utf8.encode(text))
            None => None
          }
        }),
      )
    Binaries(values) | LargeBinaries(values) | FixedBinaries(values, _) =>
      summarize_lengths(values)
    Lists(offsets, valid, _)
    | LargeLists(offsets, valid, _)
    | Maps(offsets, valid, _, _) => summarize_offsets(offsets, valid)
    FixedLists(valid, _, size) => {
      let mut count = 0
      for item in valid {
        if item {
          count += 1
        }
      }
      if count == 0 {
        NoRange
      } else {
        ByteLengthRange(size, size, count.to_int64() * size.to_int64())
      }
    }
    Structs(_, _) | Dictionaries(_, _, _, _) => NoRange
  }
  { length: self.length(), null_count: self.null_count(), range, }
}

///|
pub fn RecordBatch::summaries(
  self : RecordBatch,
) -> Array[ColumnSummary] raise ArrowError {
  self.validate()
  self.columns.map(column => column.summary())
}

///|
/// Combine summaries of batches with the same column type. NoRange acts as an
/// identity for an all-null batch, while a type mismatch is an explicit error.
pub fn ColumnSummary::combine(
  self : ColumnSummary,
  other : ColumnSummary,
) -> ColumnSummary raise ArrowError {
  if other.length > 0x7fffffff - self.length ||
    other.null_count > 0x7fffffff - self.null_count {
    raise LimitExceeded("combined summary length")
  }
  let range = match (self.range, other.range) {
    (NoRange, other) => other
    (left, NoRange) => left
    (IntRange(a, b), IntRange(c, d)) =>
      IntRange(if a < c { a } else { c }, if b > d { b } else { d })
    (Int64Range(a, b), Int64Range(c, d)) =>
      Int64Range(if a < c { a } else { c }, if b > d { b } else { d })
    (UIntRange(a, b), UIntRange(c, d)) =>
      UIntRange(if a < c { a } else { c }, if b > d { b } else { d })
    (UInt64Range(a, b), UInt64Range(c, d)) =>
      UInt64Range(if a < c { a } else { c }, if b > d { b } else { d })
    (Float32Range(a, b), Float32Range(c, d)) =>
      Float32Range(if a < c { a } else { c }, if b > d { b } else { d })
    (Float64Range(a, b), Float64Range(c, d)) =>
      Float64Range(if a < c { a } else { c }, if b > d { b } else { d })
    (ByteLengthRange(a, b, total_a), ByteLengthRange(c, d, total_b)) => {
      if total_b > 0x7fffffffffffffffL - total_a {
        raise LimitExceeded("combined byte length")
      }
      ByteLengthRange(
        if a < c {
          a
        } else {
          c
        },
        if b > d {
          b
        } else {
          d
        },
        total_a + total_b,
      )
    }
    (BooleanCounts(a, b), BooleanCounts(c, d)) => BooleanCounts(a + c, b + d)
    _ => raise Invalid("summary range type mismatch")
  }
  {
    length: self.length + other.length,
    null_count: self.null_count + other.null_count,
    range,
  }
}

///|
/// Summarize all batches without combining or copying their column arrays.
pub fn Table::summaries(self : Table) -> Array[ColumnSummary] raise ArrowError {
  let result = Array::makei(self.schema.fields.length(), _ => ColumnSummary::{
    length: 0,
    null_count: 0,
    range: NoRange,
  })
  for batch in self.batches {
    let current = batch.summaries()
    for i in 0..<current.length() {
      result[i] = result[i].combine(current[i])
    }
  }
  result
}

///|
/// Count null slots in each table column without constructing row scalars.
pub fn Table::null_counts(self : Table) -> Array[Int] {
  let counts = Array::make(self.schema.fields.length(), 0)
  for batch in self.batches {
    for i in 0..<counts.length() {
      counts[i] += batch.columns[i].null_count()
    }
  }
  counts
}
