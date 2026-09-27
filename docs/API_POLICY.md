# MoonArrow API and compatibility policy

MoonArrow's root package is the public entry point. `pkg.generated.mbti` is the
reviewable public surface; every intended change to it must accompany a
changelog entry and a migration example when existing source may break.

Version 0.x may add enum variants or adjust constructors. This is a source
compatibility change for downstream exhaustive matches; do not promise that
minor releases are source compatible. A stable 1.0 API requires downstream
feedback and a separately reviewed release decision.

`Schema`, `Field`, `Column` and `RecordBatch` contain mutable arrays. Constructors
currently retain caller arrays. A caller must not mutate a reader's schema
while reading. Writers validate batches again before encoding. New batch
operations document whether their result owns new arrays; operations with
owned results must not share mutable arrays with input batches.

`ArrowError::Invalid` means malformed data or invalid user input,
`Unsupported` means a well-formed Arrow feature outside this implementation,
and `LimitExceeded` means a configured resource budget was crossed. Public
`StreamReader` and `FileReader` retain the complete input `Bytes`; they are not
file or network I/O adapters. `IncrementalReader::push` copies incoming bytes
into a pending frame and returns decoded batches that own their data. The reader
retains its schema, at most the pending frame, and active dictionaries rather
than all completed input. `schema()` returns a defensive copy. Call `finish()`
after the final chunk: EOF at a complete message boundary is valid without an
EOS marker, while a partial frame is an error. A parsing or final-EOF error
makes the reader terminal; after EOS or successful `finish()`, it rejects
nonempty input.

`IncrementalWriter` and `FileWriter` copy their schema at construction. Call
`start()`, then `write_batch()` for each batch, then `finish()`, and send the
returned `Bytes` chunks to a caller-owned sink in that order. The stream writer
retains dictionary state; the file writer retains dictionary state and footer
indices. Neither retains completed batches or performs file or network I/O.
Calls out of order raise `Invalid`; a failed batch write or finalization leaves
the writer unusable, so create a new one to retry.
