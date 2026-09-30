# Local validation and performance record

## 2026-09-30 release 0.2.1 verification

Windows 11; moon/moonrun 0.1.20260920 (914d7da),
moonc 0.10.14+7d59c7ec9 and its matching core, Python 3.13.9,
Node.js 24.15.0, PyArrow 21.0.0. The official stable toolchain was installed
in an isolated directory under ignored `outputs/toolchains`, preserving the
machine's original toolchain. CI pins the same compiler and core version.

`python tools/verify.py` passed all **15 checks**, recording command output,
versions and exit codes in ignored `outputs/validation.json`.

| Check | Local result |
| --- | --- |
| `moon check --target all --deny-warn` | Passed with zero MoonBit warnings |
| `moon test --target all` | 63/63 passed on each of native, js, wasm and wasm-gc |
| PyArrow interoperability | 128 assertions passed on Native and 128 on JS |
| File workflows | Both scenarios passed on Native and JS |
| Independent consumer, generated interfaces, formatting and whitespace | Passed |
| Extracted Mooncakes archive | Four-backend tests, consumer, Native/JS PyArrow interoperability and file workflows passed independently |
| Core source count | 5,155 effective production lines; 5,745 physical lines |

New regressions first reproduced invalid nested scalar acceptance and an
older file footer version being accepted. The fixes reject out-of-range small
integers, non-whole-day Date64 values and incorrect fixed binary widths at
every nesting level, revalidate mutable batches and reject incompatible
dictionary schemas. Boundary values round-trip across List, LargeList,
FixedSizeList, Struct and Map. PyArrow 21's V4 messages with a V5 footer remain
supported and are verified by the independent oracle. The compiler migration
uses checked `exact_view` slices and explicit public trait extensions.

`moon coverage analyze -p shunge/arrow -- -f summary` reported
2,012/3,051 instrumented points covered (**65.9%**). This is below the proposed
85% goal; these tests do not establish full Apache Arrow integration coverage.
The September 24 benchmark results below predate the fixes.

`moon -C . publish --dry-run` completed package extraction and checking.
The registry returned **202 Accepted** for `shunge/arrow@0.2.1`, explicitly
confirming that no changes were made. This moon version nevertheless reports
`moon publish failed` and a nonzero exit code after that accepted response;
registry status must therefore also be checked after actual publication.

Reproduce with the pinned toolchain and core, Node.js and Python:

```sh
python -m pip install -r tools/requirements-interop.txt
python tools/verify.py
```

`python tools/verify_package.py` checks only the exact generated archive.
Both entry points are used by CI on Ubuntu and Windows; remote results are
separate from this local record and remain visible in GitHub Actions.

## 2026-09-24 baseline

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

## 2026-09-27 hardening verification

On Windows 11, `python tools/verify.py` passed all 14 checks and wrote the
machine-readable command log to `outputs/validation.json` (ignored by Git).
The local versions were moon 0.1.20260827, moonc 0.10.11+6ff76a5f9,
Python 3.13.9, Node.js 24.15.0 and PyArrow 21.0.0. Reproduce from a clean
checkout after installing `tools/requirements-interop.txt`:

```sh
python tools/verify.py --report outputs/validation.json
```

| Check | Local result |
| --- | --- |
| `moon check --target all --deny-warn` | Passed |
| `moon test --target all` | 50/50 passed on each of native, js, wasm and wasm-gc |
| PyArrow interoperability | 128 assertions passed on Native and 128 on JS |
| File workflows | Both scenarios passed on Native and JS |
| Independent consumer, `moon info`, `moon fmt --check`, interface and whitespace diffs | Passed |
| Core source count | 5,126 effective production lines; 5,665 physical lines |

`moon coverage analyze -p shunge/arrow -- -f summary` reported 1,851/3,051
instrumented points covered (60.7%), up from 1,788/3,035 (58.9%) before these
changes. This remains below the project's proposed 85% internal target. The
report covers the local test run, not external Arrow integration suites or
remote CI. The September 24 throughput measurements below predate these
changes and are not evidence of a speedup from the Table access changes.

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
