# Architecture and API ownership

MoonArrow has one public library package, `shunge/arrow`. The repository keeps
the codec in that package so applications can import one stable entry point.
`examples/consumer` is a separate module in `moon.work` and compiles against
public symbols only. `cmd/interop` is a test/demo transport, not a library API.

The implementation has four layers:

1. `types.mbt` and `schema_validation.mbt` define Arrow fields, columns,
   nullable values, limits and validation. `builders.mbt`, `batch_ops.mbt`,
   `table.mbt`, `selection.mbt`, `predicate.mbt`, `schema_ops.mbt`,
   `statistics.mbt` and `scalar.mbt` expose owned construction and transforms.
2. `binary.mbt` handles checked bytes, bitmaps, offsets and Arrow-specific
   FlatBuffer table operations. `metadata.mbt` handles Schema, Message and
   Footer structures. It is not a general FlatBuffers compiler.
3. `columns.mbt` recursively maps column values to field nodes and buffers.
   `dictionary.mbt` tracks dictionary IDs and cross-batch updates.
4. `ipc.mbt` implements complete-input readers and one-shot writers;
   `incremental.mbt` and `file_writer.mbt` expose framed chunks to caller-owned
   I/O sinks. `inspector.mbt` reads message/index metadata without materializing
   every batch.

The public `RecordBatch::new` and writer paths validate schema, lengths,
nullability and type matches. `Table::new` and `Table::append` copy snapshots;
`get_batch` returns a copy. These safety copies are deliberate and measured in
the benchmark, but the direct `Schema`, `Field`, `Column` and `RecordBatch`
fields are still mutable. A caller that edits those fields after validation
must revalidate before relying on them. The codec does not claim immutable
types or zero-copy views.

`ArrowError::Invalid` covers malformed input and invalid API use,
`Unsupported` covers format features outside the subset, and `LimitExceeded`
covers configured budgets. Reader limits are checked before large decoded
array allocations when practical. They cannot cap the caller's input buffer,
all returned batches or runtime overhead. State-machine errors are terminal;
construct a new reader/writer to retry.

The module still reports `version = "0.1.0"` in `moon.mod` because this
development branch is not a registry release. Public interface changes are
tracked by `moon info` in `pkg.generated.mbti`. A release will need a reviewed
version bump, migration notes, packaged-source checks and a separate publish
decision.
