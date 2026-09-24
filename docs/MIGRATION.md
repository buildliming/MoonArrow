# Migration from the published 0.1.0 subset

The GitHub development branch adds APIs and types but has not been published
as a new Mooncakes version. Code depending on `shunge/arrow@0.1.0` continues
to see the original seven-type package unless a workspace resolves the module
to this local source tree.

Existing `Schema`, `Field`, `Column`, `RecordBatch`, `read_stream`, `read_file`,
`write_stream` and `write_file` usages are intended to keep their source-level
shape. This branch extends the public enums, so exhaustive `match` expressions
over `DataType` or `Column` in downstream code must add cases or an explicit
fallback. New reader limits include nesting and dictionary budgets. Existing
calls using `ReadLimits::default()` get the new defaults automatically;
downstream code constructing `ReadLimits` with a full struct literal must add
the new fields.

For batch construction, prefer `BatchBuilder` when rows arrive individually.
Use `Table` for multi-batch transformations; it snapshots its input. Existing
`RecordBatch` columns remain publicly mutable, and serialization revalidates
them. For incremental network streams, use `IncrementalReader::push` and call
`finish()` at EOF; `StreamReader::next()` still expects a complete `Bytes`.

An independent compile and roundtrip check is available with
`moon run examples/consumer --target native`. Before a registry release,
compare `pkg.generated.mbti` with the 0.1.0 interface, test downstream code
against the exact tagged candidate and add any required breaking changes to
the release notes. This document is a source migration guide, not a promise
that every new API is frozen.
