# MoonArrow IPC format contract

This document describes the unreleased source tree after 0.1.0. The registry's
0.1.0 release has a smaller type set. MoonArrow is an Arrow IPC subset, not a
general FlatBuffers or full Arrow implementation.

## Wire format

Writers emit little-endian MetadataVersion V5 messages with 8-byte continuation
prefixes and 8-byte metadata/body alignment. Streams contain Schema, optional
DictionaryBatch messages, RecordBatch messages, and EOS. Files contain ARROW1,
framed messages, EOS, a Footer with batch/dictionary block indices, footer
length, and closing ARROW1. Readers accept V4/V5 and legacy stream prefixes.

| Layout | Supported Arrow types and representation |
| --- | --- |
| Null/Boolean | Null field node; validity and packed value bits for Boolean |
| Integers/floats | Signed and unsigned 8/16/32/64, Float32/64, little-endian fixed widths |
| Temporal | Date32 (days), Date64 (milliseconds), Timestamp/Duration (Int64 with s/ms/µs/ns unit); timestamp timezone metadata retained without conversion |
| Variable binary | Utf8/Binary with 32-bit offsets; LargeUtf8/LargeBinary with 64-bit offsets subject to MoonBit array-size limits |
| Fixed binary | FixedSizeBinary with positive width |
| Lists | List, LargeList, FixedSizeList with one child field; nested combinations use recursive field/node/buffer traversal |
| Struct/Map | Struct children; Map as List of nonnullable entry structs with nonnullable keys |
| Dictionary | Top-level fields only; Int32 indices, Utf8 or Binary values; shared IDs require compatible value type and ordered flag |

An omitted validity buffer means all slots are valid. Null slots return `None`;
their unused value bytes are not preserved. Offsets must be monotone and in
range. Valid UTF-8 is decoded strictly; BOM and embedded NUL are preserved.
Float serialization keeps bit patterns, including negative zero and NaN payloads.
UInt64 and Int64 do not pass through a JavaScript Number in the IPC codec.
Extension metadata is preserved as key/value pairs but its semantics are not
interpreted. Schema and field metadata preserve key order, duplicate keys, and
missing values.

## Reader and writer behavior

`StreamReader` takes complete input `Bytes` and returns one decoded batch per
`next()`. `FileReader` retains complete input and uses the footer to decode a
selected batch on demand. `read_stream` and `read_file` materialize all batches.
`IncrementalReader::push` accepts arbitrary byte chunks and emits completed
batches; call `finish()` to detect truncated input. It keeps at most the pending
frame and active dictionaries, apart from data retained by the caller. The
incremental stream/file writers return framed `Bytes` from `start`, each
`write_batch`, and `finish`; callers provide their own I/O sink. Failed writers
and readers have terminal behavior. None of these APIs perform disk/network I/O
or expose zero-copy views.

Stream dictionary replacement and append-only delta messages are handled.
File dictionaries are indexed by the footer; the writer rejects replacement
within a file. Unsupported dictionary value types, nested dictionaries, invalid
IDs and out-of-range indices are checked errors. File reader requires indexed
blocks and a consistent header/footer schema. It does not accept arbitrary
noncontiguous or appended/embedded Arrow files.

`BatchBuilder` accepts typed `Value` rows, verifies field compatibility, and
returns an owned `RecordBatch`. `RecordBatch` and `Table` support slice, take,
project, select, filter, predicates, and schema edits. Table construction and
append snapshot batch data; returned batches are snapshots. Public Schema,
Field, Column and RecordBatch arrays remain mutable, so a caller can still
invalidate an object it directly holds by mutating exposed fields. Writers
revalidate batches; do not mutate a reader's exposed schema while using it.

## Limits and errors

`ReadLimits::default()` sets 1,000,000 rows per batch, 8,000,000 values per
batch, 1,024 fields, 10,000 batches, 16 MiB metadata, 256 MiB body, nesting
depth 64, 8,000,000 dictionary values, and 10,000 dictionary messages. Limits
are parser budgets, not exact process-memory caps; input `Bytes`, decoded
arrays, output copies, and retained file indices also consume memory.

Malformed data and invalid API use raise `ArrowError::Invalid`; unsupported
format features raise `Unsupported`; budget violations raise `LimitExceeded`.
Unsupported input includes compressed bodies, big-endian schema, Decimal,
Union, RunEndEncoded, BinaryView/StringView/ListView, non-Int32 dictionary
indices, and custom message/footer metadata. We do not silently skip them.
Some unsupported extension metadata is retained because it is valid custom
field/schema metadata, without implementing the extension type's meaning.

## References

- [Arrow columnar and IPC specification](https://arrow.apache.org/docs/format/Columnar.html)
- [Arrow Schema.fbs](https://github.com/apache/arrow/blob/main/format/Schema.fbs)
- [Arrow Message.fbs](https://github.com/apache/arrow/blob/main/format/Message.fbs)
- [Arrow File.fbs](https://github.com/apache/arrow/blob/main/format/File.fbs)
- [Arrow integration testing](https://arrow.apache.org/docs/format/Integration.html)

Local interoperability uses PyArrow 21.0.0 as an independent implementation;
passing this corpus is not equivalent to passing the full Arrow integration
suite. See [validation results](VALIDATION.md) for exact commands and evidence.
