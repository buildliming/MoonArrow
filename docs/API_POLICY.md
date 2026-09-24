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
readers may retain an entire `Bytes` input; they are not file or network I/O
adapters. A future incremental API must have its own ownership and terminal
state contract.
