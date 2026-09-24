# Local validation and performance record

Windows 11, 2026-09-24. Moon toolchain 0.1.20260827, Python 3.13.9,
Node.js 24.15.0, PyArrow 21.0.0. This is a local result, not a claim that
remote GitHub Actions or the full Apache Arrow integration suite passed.

| Command | Result |
| --- | --- |
| `moon check --target all --deny-warn` | Passed for native, js, wasm, wasm-gc |
| `moon test --target all` | 41 passed per backend; 0 failed |
| `python tools/interop.py --target native` | 128 independent assertions passed |
| `python tools/interop.py --target js` | 128 independent assertions passed |
| `python tools/workflow.py --target native` | Both `.arrow` file scenarios passed |
| `python tools/workflow.py --target js` | Both `.arrow` file scenarios passed |
| `moon run examples/consumer --target native` | Independent module built and round-tripped 2 selected rows |
| `python tools/count_core.py --min-effective 4001` | 5,110 effective production lines; 5,647 physical lines |
| `moon info`, `moon fmt --check`, `git diff --check` | Passed after final integration |
| `moon publish --dry-run` | Local package extraction and `moon check` passed; command failed on Mooncakes API request/response body |

The four-backend tests exercise schema validation, primitive and nested layouts,
dictionary state, builder and Table operations, limits, incremental stream
boundaries, malformed inputs and original README example. PyArrow supplies
independent stream/file fixtures; the interop driver checks MoonBit decoding
and PyArrow decoding of rewritten stream/file outputs. Its 128 count is the
driver's assertion count **per target**, not 128 distinct real-world datasets.
The two workflows use real files but pass their small contents to MoonBit as
hex command-line arguments. They are integration examples, not large-file I/O.

## Reproducible debug-build benchmark

Raw data: [Native](../bench/native-windows-2026-09-24.json) and
[JavaScript](../bench/js-windows-2026-09-24.json). Run with
`python tools/bench.py --target native --output bench/native-local.json` and
the corresponding `js` command after installing `tools/requirements-bench.txt`.
The 100,000-row case loops 8 times over a mixed nullable batch and records
800,000 decoded rows. The IPC output is 2,474,112 bytes per loop.

| Target | Encode 800k rows | Decode 800k rows | Encode rows/s | Decode rows/s | Sampled peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| Native | 368 ms | 166 ms | 2.17 million | 4.82 million | 29.9 MB |
| JS/Node | 1,338 ms | 450 ms | 0.60 million | 1.78 million | 556.5 MB |

Timing is MoonBit codec-loop time; it excludes process startup, file I/O,
PyArrow validation and command-line transport. RSS is the process resident set
sampled every 5 ms and includes its runtime; a brief peak may be missed. This
single-machine debug run has no warmup distribution, confidence interval,
release-build comparison or optimization-before/after baseline. It should not
be used for a cross-library speed ranking. The smaller 1,000-row/50-iteration
case and full environment fields are in the JSON files.

`tools/count_core.py` counts hand-written production `.mbt` lines that are
nonempty and do not begin with `//` after trimming. It excludes tests,
commands, examples, generated interfaces and dependencies. This is a repo
metric, not an asserted official contest rule. See
[implementation status](IMPLEMENTATION_STATUS.zh-CN.md) for plan goals still open.
