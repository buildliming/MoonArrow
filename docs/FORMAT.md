# IPC format contract

## Encoding

Writers emit little-endian, MetadataVersion V5 messages with the 8-byte
continuation prefix. Metadata and body buffers are padded to 8-byte boundaries.
Streams contain a Schema, zero or more RecordBatch messages, then EOS.
Files contain ARROW1 plus padding, the same messages, EOS, a Footer, a 32-bit
footer length, then ARROW1. Footer blocks index complete framed record batches.

The private FlatBuffer writer uses forward references and padded table slots.
The reader supports signed vtable displacements, including shared vtables.
This is an Arrow-specific codec, not a general FlatBuffers schema compiler.

## Column layouts

| Type | Field nodes | Buffers |
| --- | --- | --- |
| Null | One length/null-count pair | None |
| Boolean | One | Validity bitmap, packed values |
| Int32 / Int64 / Float64 | One | Validity bitmap, little-endian values |
| Utf8 / Binary | One | Validity bitmap, signed 32-bit offsets, data |

Bitmap bit zero describes the first row. An omitted validity buffer means all
values are valid. Null slots are exposed as `None`. Unused bytes within null
slots are not preserved. Offset slices are checked for monotonicity and range;
valid Utf8 slots are decoded strictly, preserving BOM and embedded NUL.
Float64 serialization copies the 64-bit representation; Int64 never passes
through a JavaScript Number conversion in the IPC library.

## Reader behavior

- Accepts MetadataVersion V4 and V5, continuation and legacy prefixes.
- Accepts an explicit EOS or EOF exactly between messages; rejects trailing data
  after an explicit EOS.
- Supports schemas with no fields and record batches with zero columns and
  nonzero row counts (supply `num_rows` when constructing those batches).
- Requires file header/footer schemas to agree, blocks to be contiguous and
  their recorded sizes to match message sizes. Noncontiguous files, appended
  embedded files, dictionaries and unindexed messages are outside this subset.
- Rejects unsupported types, compression, schema feature flags and message or
  footer metadata rather than silently discarding those features.
- Schema and field metadata are UTF-8, preserve duplicates and missing values,
  and do not imply support for the semantics of any registered extension type.

`StreamReader` decodes one batch at a time from an existing in-memory input.
`FileReader` validates its index on construction and decodes a selected batch
on demand. Construction does not validate every batch body; `read_file` does.
Both readers own a reference to the complete input. Buffers and decoded values
are copied. They are not zero-copy, mmap, file-I/O or network streaming APIs.

## Bounds and mutability

Offsets are range-checked before slicing. Reader limits are applied before
decoded array allocation. Total buffer bytes per batch are bounded even if
malformed metadata aliases ranges. Limits do not bound the exact heap usage,
input allocation performed by the caller, or the aggregate size of all batches
returned by `read_stream`/`read_file`.

Public schema and column arrays remain mutable. Writers revalidate batches;
callers must not mutate a reader's schema while using that reader.
Unsupported input is not a promise of graceful recovery: after `next()` raises,
a stream reader is terminal.

## References

- [Arrow columnar and IPC specification](https://arrow.apache.org/docs/format/Columnar.html)
- [Arrow Schema.fbs](https://github.com/apache/arrow/blob/main/format/Schema.fbs)
- [Arrow Message.fbs](https://github.com/apache/arrow/blob/main/format/Message.fbs)
- [Arrow File.fbs](https://github.com/apache/arrow/blob/main/format/File.fbs)
- [Arrow integration testing](https://arrow.apache.org/docs/format/Integration.html)

Local interoperability uses PyArrow 21.0.0 as an independent implementation.
Passing this project's corpus is not equivalent to passing the full Apache
Arrow integration suite or implementing the entire Arrow specification.
