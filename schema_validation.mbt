///|
fn validate_field_schema(
  field : Field,
  depth : Int,
  seen : Array[(Int64, DataType, Bool)],
) -> Unit raise ArrowError {
  if depth > 64 { raise LimitExceeded("schema nesting depth") }
  match field.data_type {
    List | LargeList => {
      if field.children.length() != 1 { raise Invalid("List must have one child field") }
    }
    FixedSizeList(size) => {
      if size <= 0 || field.children.length() != 1 {
        raise Invalid("FixedSizeList requires positive size and one child")
      }
    }
    Struct => ()
    Dictionary(id, inner, ordered) => {
      if depth != 0 { raise Unsupported("nested dictionary fields") }
      if inner != Utf8 && inner != Binary {
        raise Unsupported("dictionary values must be Utf8 or Binary")
      }
      if !field.children.is_empty() { raise Invalid("dictionary field has children") }
      for entry in seen {
        let (found, found_type, found_ordered) = entry
        if found == id {
          if found_type != inner || found_ordered != ordered {
            raise Invalid("dictionary ID used for incompatible fields")
          }
          return
        }
      }
      seen.push((id, inner, ordered))
    }
    FixedSizeBinary(width) => if width <= 0 || !field.children.is_empty() {
      raise Invalid("invalid fixed-size binary field")
    }
    _ => if !field.children.is_empty() {
      raise Invalid("primitive field has children")
    }
  }
  for child in field.children {
    validate_field_schema(child, depth + 1, seen)
  }
}

///|
fn validate_schema(schema : Schema) -> Unit raise ArrowError {
  let seen : Array[(Int64, DataType, Bool)] = []
  for field in schema.fields {
    validate_field_schema(field, 0, seen)
  }
}
