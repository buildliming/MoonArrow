# Migration from the published 0.1.0 subset

Version 0.2.1 adds APIs and types. Upgrade with `moon add shunge/arrow@0.2.1`.
Code depending on `shunge/arrow@0.1.0` continues to see the original seven-type
package unless a workspace resolves the module to this local source tree.

Use MoonBit 0.10.14+7d59c7ec9 and its matching core for 0.2.1. Checked byte
slices use `Bytes.exact_view`; explicit trait extensions preserve the public
`equal`, `not_equal` and `to_repr` methods as implicit promotion is deprecated.

Existing `Schema`, `Field`, `Column`, `RecordBatch`, `read_stream`, `read_file`,
`write_stream` and `write_file` usages are intended to keep their source-level
shape. This release extends the public enums, so exhaustive `match` expressions
over `DataType` or `Column` in downstream code must add cases or an explicit
fallback. New reader limits include nesting and dictionary budgets. Existing
calls using `ReadLimits::default()` get the new defaults automatically;
downstream code constructing `ReadLimits` with a full struct literal must add
the new fields.

Batch construction and serialization now validate the complete schema and
all nested scalar values. Out-of-range small integers, non-whole-day Date64
values and incorrect fixed binary widths raise `Invalid` at every nesting
level. Files whose footer metadata version is older than their schema message
are rejected. PyArrow's V4 messages with a V5 footer remain supported.

For batch construction, prefer `BatchBuilder` when rows arrive individually.
Use `Table` for multi-batch transformations; it snapshots its input. Existing
`RecordBatch` columns remain publicly mutable, and serialization revalidates
them. For incremental network streams, use `IncrementalReader::push` and call
`finish()` at EOF; `StreamReader::next()` still expects a complete `Bytes`.

An independent compile and roundtrip check is available with
`moon run examples/consumer --target native`. Run `python tools/verify.py` to
check the source workspace and the extracted Mooncakes archive. Review
`pkg.generated.mbti` when upgrading downstream code. Version 0.x APIs can
still change; see [API policy](API_POLICY.md).
