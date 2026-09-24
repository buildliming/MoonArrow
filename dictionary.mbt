///|
priv struct DictionaryEntry {
  id : Int64
  values : Column
}

///|
fn dictionary_equal(left : Column, right : Column) -> Bool {
  match (left, right) {
    (Strings(a), Strings(b)) => {
      if a.length() != b.length() { return false }
      for i in 0..<a.length() { if a[i] != b[i] { return false } }
      true
    }
    (Binaries(a), Binaries(b)) => {
      if a.length() != b.length() { return false }
      for i in 0..<a.length() { if a[i] != b[i] { return false } }
      true
    }
    _ => false
  }
}

///|
fn dictionary_prefix(left : Column, right : Column) -> Bool {
  if left.data_type() != right.data_type() || left.length() > right.length() {
    return false
  }
  dictionary_equal(left, right.take_checked(Array::makei(left.length(), i => i)))
}

///|
fn schema_has_dictionary(schema : Schema) -> Bool {
  for field in schema.fields {
    if field.data_type is Dictionary(_, _, _) { return true }
  }
  false
}

///|
fn emit_dictionary_updates(
  out : Array[Byte],
  schema : Schema,
  batch : RecordBatch,
  entries : Array[DictionaryEntry],
  allow_replacement : Bool,
) -> Unit raise ArrowError {
  for i in 0..<schema.fields.length() {
    if schema.fields[i].data_type is Dictionary(id, _, _) {
      guard batch.columns[i] is Dictionaries(_, values, _, _) else {
        raise Invalid("dictionary column type mismatch")
      }
      let slot = dictionary_slot(entries, id)
      if slot >= 0 && dictionary_equal(entries[slot].values, values) { continue }
      let delta = slot >= 0 && dictionary_prefix(entries[slot].values, values)
      if slot >= 0 && !delta && !allow_replacement {
        raise Unsupported("dictionary replacement in file")
      }
      let payload = if delta {
        values.take_checked(Array::makei(values.length() - entries[slot].values.length(),
          j => entries[slot].values.length() + j))
      } else { values }
      let layout = dictionary_layout(payload)
      write_frame(out, dictionary_message(id, payload.length(), layout, delta), layout.body)
      if slot >= 0 {
        entries[slot] = { id, values, }
      } else {
        entries.push({ id, values, })
      }
    }
  }
}

///|
fn dictionary_slot(entries : Array[DictionaryEntry], id : Int64) -> Int {
  for i in 0..<entries.length() {
    if entries[i].id == id { return i }
  }
  -1
}

///|
fn dictionary_value(entries : Array[DictionaryEntry], id : Int64) -> Column raise ArrowError {
  let index = dictionary_slot(entries, id)
  if index < 0 { raise Invalid("dictionary referenced before definition") }
  entries[index].values
}

///|
fn dictionary_field(schema : Schema, id : Int64) -> Field raise ArrowError {
  for field in schema.fields {
    if field.data_type is Dictionary(found, value_type, _) && found == id {
      return Field::new("dictionary", value_type)
    }
  }
  raise Invalid("unknown dictionary id")
}

///|
fn dictionary_message(id : Int64, rows : Int, layout : BodyLayout, delta : Bool) -> Bytes {
  let out : Array[Byte] = [b'\x00', b'\x00', b'\x00', b'\x00']
  let message = fb_table(out, 4)
  put_i32(out, 0, message.pos)
  fb_int(out, message, 0, 4)
  fb_int(out, message, 1, 2)
  fb_long(out, message, 3, layout.body.length().to_int64())
  let dictionary = fb_table(out, 3)
  fb_ref(out, message, 2, dictionary.pos)
  fb_long(out, dictionary, 0, id)
  fb_ref(out, dictionary, 1, encode_batch_header(out, rows, layout))
  if delta { fb_int(out, dictionary, 2, 1) }
  align_bytes(out, 8)
  Bytes::from_array(out)
}

///|
fn dictionary_layout(values : Column) -> BodyLayout raise ArrowError {
  let schema = Schema::new([Field::new("dictionary", values.data_type())])
  encode_body(RecordBatch::new(schema, [values]))
}

///|
fn decode_dictionary_frame(
  frame : Frame,
  schema : Schema,
  entries : Array[DictionaryEntry],
  limits : ReadLimits,
  allow_replacement : Bool,
) -> Unit raise ArrowError {
  if frame.kind != 2 { raise Invalid("expected dictionary batch") }
  let id = field_long(frame.metadata, frame.header, 0)
  let field = dictionary_field(schema, id)
  let is_delta = field_int(frame.metadata, frame.header, 2, 1, 0)
  if is_delta > 1 { raise Invalid("invalid dictionary delta flag") }
  let header = required_ref(frame.metadata, frame.header, 1)
  let batch_frame = Frame::{
    metadata: frame.metadata,
    header,
    kind: 3,
    body: frame.body,
    next: frame.next,
    metadata_size: frame.metadata_size,
  }
  let batch = decode_body(batch_frame, Schema::new([field]), limits, entries)
  let values = batch.columns[0]
  let slot = dictionary_slot(entries, id)
  if is_delta == 1 {
    if slot < 0 { raise Invalid("dictionary delta before base") }
    let existing = entries[slot]
    entries[slot] = { ..existing, values: existing.values.append_checked(values), }
  } else if slot >= 0 {
    if !allow_replacement { raise Unsupported("dictionary replacement in file") }
    let existing = entries[slot]
    entries[slot] = { ..existing, values, }
  } else {
    entries.push({ id, values, })
  }
}
