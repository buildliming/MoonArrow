///|
pub(all) enum MessageKind {
  SchemaMessage
  DictionaryMessage
  BatchMessage
} derive(Eq, Debug)

///|
/// Metadata-only description of a framed IPC message. Inspectors validate
/// framing and metadata bounds, but do not decode every record batch body.
pub(all) struct MessageInfo {
  offset : Int
  metadata_bytes : Int
  body_bytes : Int
  kind : MessageKind
  rows : Int?
  dictionary_id : Int64?
} derive(Debug)

///|
pub struct StreamIndex {
  schema : Schema
  messages : Array[MessageInfo]
  has_eos : Bool
} derive(Debug)

///|
pub struct FileIndex {
  schema : Schema
  batches : Array[MessageInfo]
  dictionaries : Array[MessageInfo]
} derive(Debug)

///|
fn frame_info(
  frame : Frame,
  offset : Int,
  limits : ReadLimits,
) -> MessageInfo raise ArrowError {
  let (kind, rows, dictionary_id) = match frame.kind {
    1 => (SchemaMessage, None, None)
    2 => {
      let header = required_ref(frame.metadata, frame.header, 1)
      let count = bounded_i64(
        field_long(frame.metadata, header, 0),
        limits.max_values_per_batch,
        "dictionary rows",
      )
      (
        DictionaryMessage,
        Some(count),
        Some(field_long(frame.metadata, frame.header, 0)),
      )
    }
    3 => {
      let count = bounded_i64(
        field_long(frame.metadata, frame.header, 0),
        limits.max_rows_per_batch,
        "batch rows",
      )
      (BatchMessage, Some(count), None)
    }
    _ => raise Unsupported("IPC message kind")
  }
  {
    offset,
    metadata_bytes: frame.metadata_size,
    body_bytes: frame.body.length(),
    kind,
    rows,
    dictionary_id,
  }
}

///|
/// Scan a stream's message framing without materializing its batches.
pub fn inspect_stream(
  bytes : Bytes,
  limits? : ReadLimits = ReadLimits::default(),
) -> StreamIndex raise ArrowError {
  limits.validate()
  let first = match read_frame(bytes, 0, bytes.length(), limits) {
    Some(frame) => frame
    None => raise Invalid("missing schema message")
  }
  if first.kind != 1 {
    raise Invalid("stream must start with schema")
  }
  let schema = decode_schema(first.metadata, first.header, limits)
  let messages = [frame_info(first, 0, limits)]
  let mut offset = first.next
  let mut batches = 0
  let mut dictionaries = 0
  let mut has_eos = false
  while offset < bytes.length() {
    let start = offset
    let frame = match read_frame(bytes, offset, bytes.length(), limits) {
      None => {
        has_eos = true
        break
      }
      Some(frame) => frame
    }
    if frame.kind == 1 {
      raise Invalid("second schema message")
    }
    if frame.kind == 2 {
      dictionaries += 1
      if dictionaries > limits.max_dictionary_messages {
        raise LimitExceeded("dictionary message count")
      }
    } else if frame.kind == 3 {
      batches += 1
      if batches > limits.max_batches {
        raise LimitExceeded("batch count")
      }
    }
    messages.push(frame_info(frame, start, limits))
    offset = frame.next
  }
  { schema, messages, has_eos, }
}

///|
/// Inspect indexed Arrow file blocks without decoding record batch values.
pub fn inspect_file(
  bytes : Bytes,
  limits? : ReadLimits = ReadLimits::default(),
) -> FileIndex raise ArrowError {
  let reader = FileReader::new(bytes, limits~)
  let footer_size = read_i32(bytes, bytes.length() - 10)
  let footer_start = bytes.length() - 10 - footer_size
  let footer = slice_bytes(bytes, footer_start, footer_size)
  let root = follow_offset(footer, 0)
  let dictionary_blocks = file_blocks(footer, root, 2, limits, footer_start)
  let dictionaries = []
  for block in dictionary_blocks {
    let end = block.offset + block.metadata_size + block.body_size
    let frame = match read_frame(bytes, block.offset, end, limits) {
      Some(frame) => frame
      None => raise Invalid("dictionary block points to EOS")
    }
    dictionaries.push(frame_info(frame, block.offset, limits))
  }
  let batches = []
  for block in reader.blocks {
    let end = block.offset + block.metadata_size + block.body_size
    let frame = match read_frame(bytes, block.offset, end, limits) {
      Some(frame) => frame
      None => raise Invalid("record block points to EOS")
    }
    batches.push(frame_info(frame, block.offset, limits))
  }
  { schema: copy_schema(reader.schema), batches, dictionaries, }
}

///|
pub fn StreamIndex::num_batches(self : StreamIndex) -> Int {
  let mut count = 0
  for info in self.messages {
    if info.kind == BatchMessage {
      count += 1
    }
  }
  count
}

///|
pub fn StreamIndex::num_dictionaries(self : StreamIndex) -> Int {
  let mut count = 0
  for info in self.messages {
    if info.kind == DictionaryMessage {
      count += 1
    }
  }
  count
}

///|
pub fn StreamIndex::total_body_bytes(self : StreamIndex) -> Int64 {
  let mut total = 0L
  for info in self.messages {
    total += info.body_bytes.to_int64()
  }
  total
}

///|
pub fn FileIndex::num_batches(self : FileIndex) -> Int {
  self.batches.length()
}

///|
pub fn FileIndex::num_dictionaries(self : FileIndex) -> Int {
  self.dictionaries.length()
}

///|
pub fn FileIndex::total_body_bytes(self : FileIndex) -> Int64 {
  let mut total = 0L
  for info in self.batches {
    total += info.body_bytes.to_int64()
  }
  for info in self.dictionaries {
    total += info.body_bytes.to_int64()
  }
  total
}
