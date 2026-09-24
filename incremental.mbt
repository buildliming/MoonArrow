///|
/// Incremental Arrow IPC stream decoder. A complete frame is released after
/// each push, so memory retained by the decoder is bounded by one frame plus
/// its active dictionaries. Call finish after the final input chunk.
pub struct IncrementalReader {
  priv limits : ReadLimits
  priv mut pending : Array[Byte]
  priv mut needed : Int
  priv mut stage : Int
  priv mut prefix : Int
  priv mut metadata_size : Int
  priv mut schema_value : Schema?
  priv dictionaries : Array[DictionaryEntry]
  priv mut dictionary_messages : Int
  priv mut batches : Int
  priv mut finished : Bool
  priv mut failed : Bool
}

///|
pub fn IncrementalReader::new(
  limits? : ReadLimits = ReadLimits::default(),
) -> IncrementalReader raise ArrowError {
  limits.validate()
  {
    limits, pending: [], needed: 4, stage: 0, prefix: 0, metadata_size: 0,
    schema_value: None, dictionaries: [], dictionary_messages: 0, batches: 0,
    finished: false, failed: false,
  }
}

///|
/// Returns a defensive schema copy as soon as a complete Schema frame arrives.
pub fn IncrementalReader::schema(self : IncrementalReader) -> Schema? {
  match self.schema_value {
    Some(schema) => Some(copy_schema(schema))
    None => None
  }
}

///|
pub fn IncrementalReader::num_batches(self : IncrementalReader) -> Int {
  self.batches
}

///|
fn IncrementalReader::reset_frame(self : IncrementalReader) -> Unit {
  self.pending = []
  self.needed = 4
  self.stage = 0
  self.prefix = 0
  self.metadata_size = 0
}

///|
fn IncrementalReader::process_frame(
  self : IncrementalReader,
  output : Array[RecordBatch],
) -> Unit raise ArrowError {
  let data = Bytes::from_array(self.pending)
  let frame = match read_frame(data, 0, data.length(), self.limits) {
    Some(frame) => frame
    None => raise Invalid("unexpected empty frame")
  }
  match self.schema_value {
    None => {
      if frame.kind != 1 { raise Invalid("stream must start with a schema") }
      self.schema_value = Some(decode_schema(frame.metadata, frame.header, self.limits))
    }
    Some(schema) => {
      if frame.kind == 2 {
        if self.dictionary_messages >= self.limits.max_dictionary_messages {
          raise LimitExceeded("dictionary message count")
        }
        decode_dictionary_frame(frame, schema, self.dictionaries, self.limits, true)
        self.dictionary_messages += 1
      } else if frame.kind == 3 {
        if self.batches >= self.limits.max_batches { raise LimitExceeded("batch count") }
        output.push(decode_body(frame, schema, self.limits, self.dictionaries))
        self.batches += 1
      } else {
        raise Unsupported("unexpected IPC message type")
      }
    }
  }
  self.reset_frame()
}

///|
fn IncrementalReader::advance(
  self : IncrementalReader,
  output : Array[RecordBatch],
) -> Unit raise ArrowError {
  if self.stage == 0 {
    let input = Bytes::from_array(self.pending)
    let first = read_i32(input, 0)
    if first == -1 {
      self.prefix = 8
      self.needed = 8
      self.stage = 1
      return
    }
    self.prefix = 4
    self.metadata_size = first
    self.stage = 2
  } else if self.stage == 1 {
    self.metadata_size = read_i32(Bytes::from_array(self.pending), 4)
    self.stage = 2
  } else if self.stage == 2 {
    let metadata = slice_bytes(Bytes::from_array(self.pending), self.prefix,
      self.metadata_size)
    let root = follow_offset(metadata, 0)
    let body_size = bounded_i64(field_long(metadata, root, 3),
      self.limits.max_body_bytes, "body size")
    if body_size > 0x7fffffff - self.pending.length() {
      raise LimitExceeded("frame size")
    }
    self.needed = self.pending.length() + body_size
    self.stage = 3
    if body_size == 0 { self.process_frame(output) }
    return
  } else {
    self.process_frame(output)
    return
  }
  if self.metadata_size < 0 { raise Invalid("negative metadata size") }
  if self.metadata_size > self.limits.max_metadata_bytes {
    raise LimitExceeded("metadata size")
  }
  if self.metadata_size == 0 {
    if self.schema_value is None { raise Invalid("EOS before schema") }
    self.finished = true
    self.reset_frame()
    return
  }
  if self.metadata_size > 0x7fffffff - self.prefix {
    raise LimitExceeded("frame size")
  }
  self.needed = self.prefix + self.metadata_size
  if self.pending.length() == self.needed { self.advance(output) }
}

///|
/// Feed any byte chunk, including an empty one. Complete batches are returned
/// in stream order. An error makes this reader terminal.
pub fn IncrementalReader::push(
  self : IncrementalReader,
  chunk : Bytes,
) -> Array[RecordBatch] raise ArrowError {
  if self.failed { raise Invalid("incremental reader failed") }
  if self.finished {
    if !chunk.is_empty() { raise Invalid("bytes after end-of-stream marker") }
    return []
  }
  self.failed = true
  let output = []
  for byte in chunk {
    if self.finished { raise Invalid("bytes after end-of-stream marker") }
    self.pending.push(byte)
    if self.pending.length() == self.needed { self.advance(output) }
  }
  self.failed = false
  output
}

///|
/// Signal final EOF. Clean EOF at a message boundary is allowed without EOS.
pub fn IncrementalReader::finish(self : IncrementalReader) -> Unit raise ArrowError {
  if self.failed { raise Invalid("incremental reader failed") }
  self.failed = true
  if self.schema_value is None { raise Invalid("missing schema message") }
  if !self.pending.is_empty() { raise Invalid("truncated IPC stream") }
  self.finished = true
  self.failed = false
}

///|
/// Incremental writer for the Arrow IPC stream format. Its output chunks can
/// be written to a file or network sink without buffering completed batches.
pub struct IncrementalWriter {
  priv schema_value : Schema
  priv dictionaries : Array[DictionaryEntry]
  priv mut started : Bool
  priv mut finished : Bool
  priv mut failed : Bool
}

///|
pub fn IncrementalWriter::new(schema : Schema) -> IncrementalWriter raise ArrowError {
  validate_schema(schema)
  { schema_value: copy_schema(schema), dictionaries: [], started: false,
    finished: false, failed: false, }
}

///|
pub fn IncrementalWriter::start(self : IncrementalWriter) -> Bytes raise ArrowError {
  if self.started || self.finished || self.failed {
    raise Invalid("stream writer already started or finished")
  }
  self.started = true
  let out : Array[Byte] = []
  write_frame(out, schema_message(self.schema_value,
    replacement=schema_has_dictionary(self.schema_value)), b"")
  Bytes::from_array(out)
}

///|
/// Return one framed batch and any preceding dictionary update messages.
pub fn IncrementalWriter::write_batch(
  self : IncrementalWriter,
  batch : RecordBatch,
) -> Bytes raise ArrowError {
  if !self.started || self.finished || self.failed {
    raise Invalid("stream writer is not active")
  }
  self.failed = true
  batch.validate()
  if batch.schema != self.schema_value { raise Invalid("batch schema mismatch") }
  let out : Array[Byte] = []
  emit_dictionary_updates(out, self.schema_value, batch, self.dictionaries, true)
  let layout = encode_body(batch)
  write_frame(out, batch_message(batch.num_rows, layout), layout.body)
  self.failed = false
  Bytes::from_array(out)
}

///|
pub fn IncrementalWriter::finish(self : IncrementalWriter) -> Bytes raise ArrowError {
  if !self.started || self.finished || self.failed {
    raise Invalid("stream writer is not active")
  }
  self.finished = true
  let out : Array[Byte] = []
  write_eos(out)
  Bytes::from_array(out)
}
