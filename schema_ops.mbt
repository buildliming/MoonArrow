///|
/// Find one field by name. Duplicate names are ambiguous and are rejected.
pub fn Schema::field_index(
  self : Schema,
  name : String,
) -> Int raise ArrowError {
  let mut found = -1
  for i in 0..<self.fields.length() {
    if self.fields[i].name == name {
      if found >= 0 {
        raise Invalid("ambiguous field name: " + name)
      }
      found = i
    }
  }
  if found < 0 {
    raise Invalid("unknown field name: " + name)
  }
  found
}

///|
/// Select schema fields by index while copying field and metadata arrays.
pub fn Schema::project(
  self : Schema,
  indices : Array[Int],
) -> Schema raise ArrowError {
  let fields = []
  for index in indices {
    if index < 0 || index >= self.fields.length() {
      raise Invalid("schema field index out of range")
    }
    fields.push(copy_field(self.fields[index]))
  }
  Schema::new(fields, metadata=self.metadata.map(kv => kv))
}

///|
pub fn Schema::rename(
  self : Schema,
  index : Int,
  name : String,
) -> Schema raise ArrowError {
  if index < 0 || index >= self.fields.length() {
    raise Invalid("rename field index out of range")
  }
  let fields = self.fields.map(field => copy_field(field))
  let old = fields[index]
  fields[index] = Field::new(
    name,
    old.data_type,
    nullable=old.nullable,
    metadata=old.metadata,
    children=old.children,
  )
  Schema::new(fields, metadata=self.metadata.map(kv => kv))
}

///|
pub fn Schema::drop_field(
  self : Schema,
  index : Int,
) -> Schema raise ArrowError {
  if index < 0 || index >= self.fields.length() {
    raise Invalid("drop field index out of range")
  }
  let indices = []
  for i in 0..<self.fields.length() {
    if i != index {
      indices.push(i)
    }
  }
  self.project(indices)
}

///|
pub fn Table::rename(
  self : Table,
  index : Int,
  name : String,
) -> Table raise ArrowError {
  let schema = self.schema.rename(index, name)
  let batches = []
  for batch in self.batches {
    batches.push(batch.rename(index, name))
  }
  Table::new(schema, batches)
}

///|
pub fn Table::drop_column(self : Table, index : Int) -> Table raise ArrowError {
  let schema = self.schema.drop_field(index)
  let batches = []
  for batch in self.batches {
    batches.push(batch.drop_column(index))
  }
  Table::new(schema, batches)
}

///|
/// Select named fields in request order. Duplicate input names are retained.
pub fn RecordBatch::select(
  self : RecordBatch,
  names : Array[String],
) -> RecordBatch raise ArrowError {
  let indices = []
  for name in names {
    indices.push(self.schema.field_index(name))
  }
  self.project(indices)
}

///|
pub fn Table::select(
  self : Table,
  names : Array[String],
) -> Table raise ArrowError {
  let indices = []
  for name in names {
    indices.push(self.schema.field_index(name))
  }
  self.project(indices)
}

///|
/// Rename a field without changing its data type, metadata or values.
pub fn RecordBatch::rename(
  self : RecordBatch,
  index : Int,
  name : String,
) -> RecordBatch raise ArrowError {
  self.validate()
  if index < 0 || index >= self.schema.fields.length() {
    raise Invalid("rename field index out of range")
  }
  let fields = self.schema.fields.map(field => copy_field(field))
  let old = fields[index]
  fields[index] = Field::new(
    name,
    old.data_type,
    nullable=old.nullable,
    metadata=old.metadata,
    children=old.children,
  )
  let schema = Schema::new(fields, metadata=self.schema.metadata.map(kv => kv))
  let columns = self.columns.map(column => {
    column.take_checked(Array::makei(self.num_rows, i => i))
  })
  RecordBatch::new(schema, columns, num_rows=self.num_rows)
}

///|
/// Replace a column and its field together, keeping the same row count.
pub fn RecordBatch::replace_column(
  self : RecordBatch,
  index : Int,
  field : Field,
  column : Column,
) -> RecordBatch raise ArrowError {
  self.validate()
  if index < 0 || index >= self.columns.length() {
    raise Invalid("replace field index out of range")
  }
  if column.length() != self.num_rows || column.data_type() != field.data_type {
    raise Invalid("replacement column type or length mismatch")
  }
  let fields = self.schema.fields.map(item => copy_field(item))
  let columns = self.columns.map(item => {
    item.take_checked(Array::makei(self.num_rows, i => i))
  })
  fields[index] = copy_field(field)
  columns[index] = column.take_checked(Array::makei(self.num_rows, i => i))
  RecordBatch::new(
    Schema::new(fields, metadata=self.schema.metadata.map(kv => kv)),
    columns,
    num_rows=self.num_rows,
  )
}

///|
/// Insert one field and column at index, including at the end of a batch.
pub fn RecordBatch::insert_column(
  self : RecordBatch,
  index : Int,
  field : Field,
  column : Column,
) -> RecordBatch raise ArrowError {
  self.validate()
  if index < 0 || index > self.columns.length() {
    raise Invalid("insert field index out of range")
  }
  if column.length() != self.num_rows || column.data_type() != field.data_type {
    raise Invalid("inserted column type or length mismatch")
  }
  let fields = []
  let columns = []
  for i in 0..<(self.columns.length() + 1) {
    if i == index {
      fields.push(copy_field(field))
      columns.push(column.take_checked(Array::makei(self.num_rows, j => j)))
    } else {
      let old = if i < index { i } else { i - 1 }
      fields.push(copy_field(self.schema.fields[old]))
      columns.push(
        self.columns[old].take_checked(Array::makei(self.num_rows, j => j)),
      )
    }
  }
  RecordBatch::new(
    Schema::new(fields, metadata=self.schema.metadata.map(kv => kv)),
    columns,
    num_rows=self.num_rows,
  )
}

///|
pub fn RecordBatch::drop_column(
  self : RecordBatch,
  index : Int,
) -> RecordBatch raise ArrowError {
  if index < 0 || index >= self.columns.length() {
    raise Invalid("drop field index out of range")
  }
  let indices = []
  for i in 0..<self.columns.length() {
    if i != index {
      indices.push(i)
    }
  }
  self.project(indices)
}

///|
/// Split one batch into smaller batches; a zero-row batch remains one batch.
pub fn RecordBatch::split_rows(
  self : RecordBatch,
  max_rows : Int,
) -> Array[RecordBatch] raise ArrowError {
  self.validate()
  if max_rows <= 0 {
    raise Invalid("max_rows must be positive")
  }
  if self.num_rows == 0 {
    return [self.slice(0, 0)]
  }
  let result = []
  let mut start = 0
  while start < self.num_rows {
    let remaining = self.num_rows - start
    let length = if remaining < max_rows { remaining } else { max_rows }
    result.push(self.slice(start, length))
    start += length
  }
  result
}
