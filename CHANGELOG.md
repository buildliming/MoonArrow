# Changelog

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
network streaming are not implemented. The module has not been published to
Mooncakes. See `docs/FORMAT.md` for the complete supported contract.

The existing repository history and MIT license are retained. The first code
delivery is split into ten commits documented in `docs/INITIAL_COMMITS.zh-CN.md`.
