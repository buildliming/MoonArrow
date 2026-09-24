///|
/// Incremental Arrow IPC file writer. Completed batch chunks can be sent
/// directly to a sink. The writer retains footer block indices and dictionaries.
pub struct FileWriter {
  priv schema_value : Schema
  priv blocks : Array[FileBlock]
  priv dictionary_blocks : Array[FileBlock]
  priv dictionaries : Array[DictionaryEntry]
  priv mut offset : Int
  priv mut started : Bool
  priv mut finished : Bool
  priv mut failed : Bool
}

///|
pub fn FileWriter::new(schema : Schema) -> FileWriter raise ArrowError {
  validate_schema(schema)
  {
    schema_value: copy_schema(schema), blocks: [], dictionary_blocks: [],
    dictionaries: [], offset: 0, started: false, finished: false, failed: false,
  }
}

///|
pub fn FileWriter::start(self : FileWriter) -> Bytes raise ArrowError {
  if self.started || self.finished || self.failed {
    raise Invalid("file writer already started or finished")
  }
  let out : Array[Byte] = []
  append_bytes(out, b"ARROW1")
  align_bytes(out, 8)
  write_frame(out, schema_message(self.schema_value), b"")
  self.offset = out.length()
  self.started = true
  Bytes::from_array(out)
}

///|
fn FileWriter::append_dictionary(
  self : FileWriter,
  out : Array[Byte],
  id : Int64,
  values : Column,
) -> Unit raise ArrowError {
  let slot = dictionary_slot(self.dictionaries, id)
  if slot >= 0 {
    if !dictionary_equal(self.dictionaries[slot].values, values) {
      raise Unsupported("dictionary replacement in file")
    }
    return
  }
  let layout = dictionary_layout(values)
  let metadata = dictionary_message(id, values.length(), layout, false)
  if metadata.length() > 0x7fffffff - self.offset - out.length() - 8 ||
    layout.body.length() > 0x7fffffff - self.offset - out.length() - metadata.length() - 8 {
    raise LimitExceeded("file size")
  }
  self.dictionary_blocks.push(FileBlock::{
    offset: self.offset + out.length(), metadata_size: 8 + metadata.length(),
    body_size: layout.body.length(),
  })
  write_frame(out, metadata, layout.body)
  self.dictionaries.push({ id, values, })
}

///|
/// Return the framed batch and any first-use dictionary messages.
pub fn FileWriter::write_batch(self : FileWriter, batch : RecordBatch) -> Bytes raise ArrowError {
  if !self.started || self.finished || self.failed {
    raise Invalid("file writer is not active")
  }
  self.failed = true
  batch.validate()
  if batch.schema != self.schema_value { raise Invalid("batch schema mismatch") }
  let out : Array[Byte] = []
  for i in 0..<self.schema_value.fields.length() {
    if self.schema_value.fields[i].data_type is Dictionary(id, _, _) {
      guard batch.columns[i] is Dictionaries(_, values, _, _) else {
        raise Invalid("dictionary column type mismatch")
      }
      self.append_dictionary(out, id, values)
    }
  }
  let layout = encode_body(batch)
  let metadata = batch_message(batch.num_rows, layout)
  if metadata.length() > 0x7fffffff - self.offset - out.length() - 8 ||
    layout.body.length() > 0x7fffffff - self.offset - out.length() - metadata.length() - 8 {
    raise LimitExceeded("file size")
  }
  self.blocks.push(FileBlock::{
    offset: self.offset + out.length(), metadata_size: 8 + metadata.length(),
    body_size: layout.body.length(),
  })
  write_frame(out, metadata, layout.body)
  if out.length() > 0x7fffffff - self.offset { raise LimitExceeded("file size") }
  self.offset += out.length()
  self.failed = false
  Bytes::from_array(out)
}

///|
/// Return EOS, footer, footer length and trailing magic.
pub fn FileWriter::finish(self : FileWriter) -> Bytes raise ArrowError {
  if !self.started || self.finished || self.failed {
    raise Invalid("file writer is not active")
  }
  self.failed = true
  let out : Array[Byte] = []
  write_eos(out)
  let footer = encode_footer(self.schema_value, self.blocks, self.dictionary_blocks)
  if footer.length() > 0x7fffffff - self.offset - 18 {
    raise LimitExceeded("file footer size")
  }
  append_bytes(out, footer)
  put_i32(out, reserve(out, 4), footer.length())
  append_bytes(out, b"ARROW1")
  self.finished = true
  self.failed = false
  Bytes::from_array(out)
}
