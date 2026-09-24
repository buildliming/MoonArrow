# Changelog

## Unreleased — ecosystem build-out

- Added numeric widths, temporal types, large/fixed binary, recursive List,
  LargeList, FixedSizeList, Struct and Map IPC layouts.
- Added top-level Int32-index Utf8/Binary dictionaries, stream replacement and
  delta handling, file dictionary indices, and bounded dictionary state.
- Added owned row builder, Table/RecordBatch transforms, predicates, typed
  scalar access, summaries, and stream/file metadata inspection.
- Added incremental stream reader/writer and chunked file writer APIs.
- Expanded four-backend tests and PyArrow interoperability fixtures; added
  independent consumer, two file workflows, source-line gate and benchmarks.

This is a source-tree changelog. The `moon.mod` version remains 0.1.0 until a
separate reviewed registry release. New APIs are not available from the
published 0.1.0 package.

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
