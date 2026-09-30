///|
fn rejects_nested_column(
  data_type : @arrow.DataType,
  column : @arrow.Column,
) -> Bool {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("items", List, children=[
      @arrow.Field::new("item", data_type),
    ]),
  ])
  try {
    ignore(@arrow.RecordBatch::new(schema, [Lists([0, 1], [true], column)]))
    false
  } catch {
    @arrow.Invalid(_) => true
    _ => false
  }
}

///|
test "nested Int8 values reject overflow" {
  assert_true(rejects_nested_column(Int8, Int8s([Some(128)])))
  assert_true(rejects_nested_column(Int8, Int8s([Some(-129)])))
}

///|
test "nested Int16 values reject overflow" {
  assert_true(rejects_nested_column(Int16, Int16s([Some(32768)])))
  assert_true(rejects_nested_column(Int16, Int16s([Some(-32769)])))
}

///|
test "nested UInt8 values reject overflow" {
  assert_true(rejects_nested_column(UInt8, UInt8s([Some(256)])))
  assert_true(rejects_nested_column(UInt8, UInt8s([Some(-1)])))
}

///|
test "nested UInt16 values reject overflow" {
  assert_true(rejects_nested_column(UInt16, UInt16s([Some(65536)])))
  assert_true(rejects_nested_column(UInt16, UInt16s([Some(-1)])))
}

///|
test "nested Date64 values must represent whole days" {
  assert_true(rejects_nested_column(Date64, Date64s([Some(1L)])))
  assert_true(rejects_nested_column(Date64, Date64s([Some(-1L)])))
}

///|
test "nested fixed binary values must match width" {
  assert_true(
    rejects_nested_column(FixedSizeBinary(2), FixedBinaries([Some(b"x")], 2)),
  )
  assert_true(
    rejects_nested_column(FixedSizeBinary(2), FixedBinaries([Some(b"xyz")], 2)),
  )
}

///|
test "writers revalidate mutated nested values" {
  let values = [Some(127)]
  let schema = @arrow.Schema::new([
    @arrow.Field::new("items", List, children=[@arrow.Field::new("item", Int8)]),
  ])
  let batch = @arrow.RecordBatch::new(schema, [
    Lists([0, 1], [true], Int8s(values)),
  ])
  values[0] = Some(128)
  let stream_rejected = try {
    ignore(@arrow.write_stream(schema, [batch]))
    false
  } catch {
    @arrow.Invalid(_) => true
    _ => false
  }
  let file_rejected = try {
    ignore(@arrow.write_file(schema, [batch]))
    false
  } catch {
    @arrow.Invalid(_) => true
    _ => false
  }
  assert_true(stream_rejected)
  assert_true(file_rejected)
}

///|
test "nested scalar boundaries survive all supported containers" {
  let fields = [
    @arrow.Field::new("i8", Int8),
    @arrow.Field::new("i16", Int16),
    @arrow.Field::new("u8", UInt8),
    @arrow.Field::new("u16", UInt16),
    @arrow.Field::new("day", Date64),
    @arrow.Field::new("bytes", FixedSizeBinary(2)),
  ]
  let columns : Array[@arrow.Column] = [
    Int8s([Some(-128), Some(127), None]),
    Int16s([Some(-32768), Some(32767), None]),
    UInt8s([Some(0), Some(255), None]),
    UInt16s([Some(0), Some(65535), None]),
    Date64s([Some(-86400000L), Some(86400000L), None]),
    FixedBinaries([Some(b"ab"), Some(b"cd"), None], 2),
  ]
  for i in 0..<fields.length() {
    let field = fields[i]
    let child = columns[i]
    let entries = @arrow.Field::new("entries", Struct, nullable=false, children=[
      @arrow.Field::new("key", Int32, nullable=false),
      field,
    ])
    let schema = @arrow.Schema::new([
      @arrow.Field::new("list", List, children=[field]),
      @arrow.Field::new("large", LargeList, children=[field]),
      @arrow.Field::new("fixed", FixedSizeList(3), children=[field]),
      @arrow.Field::new("struct", Struct, children=[
        @arrow.Field::new("inner", List, children=[field]),
      ]),
      @arrow.Field::new("map", Map(false), children=[entries]),
    ])
    let batch = @arrow.RecordBatch::new(schema, [
      Lists([0, 3], [true], child),
      LargeLists([0, 3], [true], child),
      FixedLists([true], child, 3),
      Structs([true], [Lists([0, 3], [true], child)]),
      Maps(
        [0, 3],
        [true],
        Structs([true, true, true], [Int32s([Some(0), Some(1), Some(2)]), child]),
        false,
      ),
    ])
    for
      bytes in [
        @arrow.write_stream(schema, [batch]),
        @arrow.write_file(schema, [batch]),
      ] {
      let decoded = if bytes.has_prefix(b"ARROW1") {
        @arrow.read_file(bytes)
      } else {
        @arrow.read_stream(bytes)
      }
      assert_eq(
        @arrow.write_stream(decoded.schema, decoded.batches),
        @arrow.write_stream(schema, [batch]),
      )
    }
  }
}
