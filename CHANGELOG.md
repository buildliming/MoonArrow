# Changelog

## 0.2.1 — 2026-09-30

- Pin CI to MoonBit 0.10.14+7d59c7ec9 and its matching core.
- Migrate checked byte slices to `exact_view` and explicitly export existing
  trait methods; generated interfaces now list these methods.
- Revalidate schemas and scalar values recursively, preventing nested integer
  truncation and invalid Date64 or fixed binary values from being serialized.
- Reject Arrow file footers older than their schema message, preserving
  compatibility with PyArrow's V4 messages and V5 footer.
- Added regressions for nested value bounds, mutation and malformed wire data;
  test valid boundary values across all five supported nested containers.
- Validate the extracted Mooncakes archive on all four backends, including
  its consumer, PyArrow interoperability and file workflows. CI uses the same
  verification entry point and uploads its JSON report on success or failure.

## 0.2.0 — Ecosystem build-out

- Isolated stream/file reader schemas and dictionary values from mutable
  returned batches, and snapshotted dictionary state in incremental writers.
- Avoided whole-batch copies for single-row Table access and grouped adjacent
  selections from the same source batch.
- Added a reproducible full verification report, kept Python interoperability
  checks active under `-O`, and added the JS file workflow to CI.
- Added numeric widths, temporal types, large/fixed binary, recursive List,
  LargeList, FixedSizeList, Struct and Map IPC layouts.
- Added top-level Int32-index Utf8/Binary dictionaries, stream replacement and
  delta handling, file dictionary indices, and bounded dictionary state.
- Added owned row builder, Table/RecordBatch transforms, predicates, typed
  scalar access, summaries, and stream/file metadata inspection.
- Added incremental stream reader/writer and chunked file writer APIs.
- Expanded four-backend tests and PyArrow interoperability fixtures; added
  independent consumer, two file workflows, source-line gate and benchmarks.

The expanded APIs require `shunge/arrow@0.2.0` or newer. Exhaustive enum matches and complete
`ReadLimits` literals may need updates; see [migration](docs/MIGRATION.md).

## 0.1.0 — Initial implementation

### Added

- Pure MoonBit schemas and nullable columns for Null, Boolean, Int32, Int64,
  Float64, Utf8 and Binary.
- Checked little-endian and Arrow-specific FlatBuffer metadata codecs.
- IPC stream and file writers, V4/V5 readers, legacy framing and footer-indexed
  record batch access over in-memory bytes.
- Ordered schema/field metadata and configurable parsing limits.
- Four-backend tests, a PyArrow-generated fixture and Native/JS interoperability
  tests against PyArrow 21.0.0.
- Runnable example, format contract, contribution guide and CI configuration.

### Scope

This version implements a subset of Arrow IPC. Nested types, dictionaries,
compression, temporal types, additional numeric types, zero-copy views and
network streaming are not implemented. The Mooncakes module name is `shunge/arrow`. See `docs/FORMAT.md` for the complete supported contract.

The existing repository history and MIT license are retained. The first code
delivery is split into ten commits documented in `docs/INITIAL_COMMITS.zh-CN.md`.
