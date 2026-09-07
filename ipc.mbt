///|
fn write_frame(out : Array[Byte], metadata : Bytes, body : Bytes) -> Unit {
  let start = reserve(out, 8)
  put_i32(out, start, -1)
  put_i32(out, start + 4, metadata.length())
  append_bytes(out, metadata)
  append_bytes(out, body)
}

///|
fn write_eos(out : Array[Byte]) -> Unit {
  let p = reserve(out, 8)
  put_i32(out, p, -1)
}

///|
fn validate_batches(
  schema : Schema,
  batches : Array[RecordBatch],
) -> Unit raise ArrowError {
  for batch in batches {
    batch.validate()
    if batch.schema != schema {
      raise Invalid("batch schema mismatch")
    }
  }
}

///|
/// Write an uncompressed V5 IPC stream, including a schema and end marker.
pub fn write_stream(
  schema : Schema,
  batches : Array[RecordBatch],
) -> Bytes raise ArrowError {
  validate_batches(schema, batches)
  let out : Array[Byte] = []
  write_frame(out, schema_message(schema), b"")
  for batch in batches {
    let layout = encode_body(batch)
    write_frame(out, batch_message(batch.num_rows, layout), layout.body)
  }
  write_eos(out)
  Bytes::from_array(out)
}

///|
/// Decode batches on demand from an in-memory stream. This retains the input
/// Bytes; it is not a network push parser. Both explicit EOS and clean EOF work.
pub struct StreamReader {
  schema : Schema
  priv data : Bytes
  priv limits : ReadLimits
  priv mut offset : Int
  priv mut count : Int
  priv mut finished : Bool
}

///|
pub fn StreamReader::new(
  data : Bytes,
  limits? : ReadLimits = ReadLimits::default(),
) -> StreamReader raise ArrowError {
  limits.validate()
  let frame = match read_frame(data, 0, data.length(), limits) {
    Some(frame) => frame
    None => raise Invalid("missing schema message")
  }
  if frame.kind != 1 {
    raise Invalid("stream must start with a schema")
  }
  let schema = decode_schema(frame.metadata, frame.header, limits)
  { schema, data, limits, offset: frame.next, count: 0, finished: false, }
}

///|
/// Return the next batch. On error the reader becomes terminal.
pub fn StreamReader::next(self : StreamReader) -> RecordBatch? raise ArrowError {
  if self.finished {
    return None
  }
  self.finished = true
  let frame = match
    read_frame(self.data, self.offset, self.data.length(), self.limits) {
    None => return None
    Some(frame) => frame
  }
  if self.count >= self.limits.max_batches {
    raise LimitExceeded("batch count")
  }
  let result = decode_body(frame, self.schema, self.limits)
  self.offset = frame.next
  self.count += 1
  self.finished = false
  Some(result)
}

///|
/// Read and materialize all batches of an IPC stream.
pub fn read_stream(
  data : Bytes,
  limits? : ReadLimits = ReadLimits::default(),
) -> IpcData raise ArrowError {
  let reader = StreamReader::new(data, limits~)
  let batches = []
  while reader.next() is Some(batch) {
    batches.push(batch)
  }
  { schema: reader.schema, batches, }
}

///|
priv struct FileBlock {
  offset : Int
  metadata_size : Int
  body_size : Int
}

///|
fn encode_footer(schema : Schema, blocks : Array[FileBlock]) -> Bytes {
  let out : Array[Byte] = [b'\x00', b'\x00', b'\x00', b'\x00']
  let footer = fb_table(out, 4)
  put_i32(out, 0, footer.pos)
  fb_int(out, footer, 0, 4)
  fb_ref(out, footer, 1, encode_schema(out, schema))
  let vector = fb_vector(out, blocks.length(), 24, 8)
  fb_ref(out, footer, 3, vector)
  for i in 0..<blocks.length() {
    let block = blocks[i]
    let p = vector + 4 + i * 24
    put_i64(out, p, block.offset.to_int64())
    put_i32(out, p + 8, block.metadata_size)
    put_i64(out, p + 16, block.body_size.to_int64())
  }
  align_bytes(out, 8)
  Bytes::from_array(out)
}

///|
/// Write an uncompressed Arrow IPC file with footer-indexed record batches.
/// This supports the implemented type subset of uncompressed Feather V2.
pub fn write_file(
  schema : Schema,
  batches : Array[RecordBatch],
) -> Bytes raise ArrowError {
  validate_batches(schema, batches)
  let out : Array[Byte] = []
  append_bytes(out, b"ARROW1")
  align_bytes(out, 8)
  write_frame(out, schema_message(schema), b"")
  let blocks = []
  for batch in batches {
    let layout = encode_body(batch)
    let metadata = batch_message(batch.num_rows, layout)
    blocks.push(FileBlock::{
      offset: out.length(),
      metadata_size: 8 + metadata.length(),
      body_size: layout.body.length(),
    })
    write_frame(out, metadata, layout.body)
  }
  write_eos(out)
  let footer = encode_footer(schema, blocks)
  append_bytes(out, footer)
  put_i32(out, reserve(out, 4), footer.length())
  append_bytes(out, b"ARROW1")
  Bytes::from_array(out)
}

///|
/// Footer-indexed access to record batches in an in-memory Arrow IPC file.
pub struct FileReader {
  schema : Schema
  priv data : Bytes
  priv limits : ReadLimits
  priv blocks : Array[FileBlock]
}

///|
pub fn FileReader::new(
  data : Bytes,
  limits? : ReadLimits = ReadLimits::default(),
) -> FileReader raise ArrowError {
  limits.validate()
  if data.length() < 18 ||
    !data.has_prefix(b"ARROW1") ||
    !data.has_suffix(b"ARROW1") {
    raise Invalid("invalid Arrow file magic or size")
  }
  let footer_size = read_i32(data, data.length() - 10)
  if footer_size < 0 || footer_size > data.length() - 18 {
    raise Invalid("invalid footer size")
  }
  if footer_size > limits.max_metadata_bytes {
    raise LimitExceeded("footer size")
  }
  let footer_start = data.length() - 10 - footer_size
  let footer = slice_bytes(data, footer_start, footer_size)
  let root = follow_offset(footer, 0)
  let version = field_int(footer, root, 0, 2, 0)
  if version != 3 && version != 4 {
    raise Unsupported("footer metadata version")
  }
  let schema = decode_schema(footer, required_ref(footer, root, 1), limits)
  let (_, dictionaries) = vector_info(footer, root, 2, 24, limits.max_batches)
  if dictionaries != 0 {
    raise Unsupported("dictionary blocks")
  }
  let (_, custom) = vector_info(footer, root, 4, 4, limits.max_fields)
  if custom != 0 {
    raise Unsupported("footer custom metadata")
  }
  let first = match read_frame(data, 8, footer_start, limits) {
    Some(frame) => frame
    None => raise Invalid("missing file schema message")
  }
  if first.kind != 1 ||
    decode_schema(first.metadata, first.header, limits) != schema {
    raise Invalid("header/footer schema mismatch")
  }
  let (p, count) = vector_info(footer, root, 3, 24, limits.max_batches)
  let blocks = []
  let mut last_end = first.next
  for i in 0..<count {
    let offset = bounded_i64(
      read_i64(footer, p + i * 24),
      footer_start,
      "file block offset",
    )
    let metadata_size = read_i32(footer, p + i * 24 + 8)
    let body_size = bounded_i64(
      read_i64(footer, p + i * 24 + 16),
      limits.max_body_bytes,
      "file block body size",
    )
    if offset != last_end ||
      metadata_size < 4 ||
      metadata_size > footer_start - offset {
      raise Invalid("invalid or noncontiguous file block")
    }
    if metadata_size - 8 > limits.max_metadata_bytes {
      raise LimitExceeded("file block metadata size")
    }
    if body_size > footer_start - offset - metadata_size {
      raise Invalid("file block exceeds footer")
    }
    last_end = offset + metadata_size + body_size
    blocks.push(FileBlock::{ offset, metadata_size, body_size, })
  }
  // Writers may omit the EOS marker. Otherwise only a valid EOS may follow.
  if read_frame(data, last_end, footer_start, limits) is Some(_) {
    raise Invalid("unindexed file message")
  }
  { schema, data, limits, blocks, }
}

///|
pub fn FileReader::num_batches(self : FileReader) -> Int {
  self.blocks.length()
}

///|
pub fn FileReader::get_batch(
  self : FileReader,
  index : Int,
) -> RecordBatch raise ArrowError {
  if index < 0 || index >= self.blocks.length() {
    raise Invalid("batch index out of range")
  }
  let block = self.blocks[index]
  let frame = match
    read_frame(
      self.data,
      block.offset,
      block.offset + block.metadata_size + block.body_size,
      self.limits,
    ) {
    None => raise Invalid("file block points to EOS")
    Some(frame) => frame
  }
  if frame.metadata_size != block.metadata_size ||
    frame.body.length() != block.body_size {
    raise Invalid("footer block lengths differ from message")
  }
  decode_body(frame, self.schema, self.limits)
}

///|
pub fn read_file(
  data : Bytes,
  limits? : ReadLimits = ReadLimits::default(),
) -> IpcData raise ArrowError {
  let reader = FileReader::new(data, limits~)
  let batches = []
  for i in 0..<reader.num_batches() {
    batches.push(reader.get_batch(i))
  }
  { schema: reader.schema, batches, }
}
