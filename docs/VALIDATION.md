# Local validation and performance record

## 2026-11-12 release 0.2.3

Version 0.2.3 combines the verified 0.2.2 compatibility fixes with the aligned
23-check source and 15-check extracted-archive workflow. The consumer
dependency, README installation commands and changelog use the release version.
The four-backend API and numerical test results from the aligned worktrees
remain applicable to this verification-only maintenance update.
The final 0.2.3 source passed all 23 checks, including 15 extracted-archive
checks, with 63/63 tests on each of the four backends. Its command log is saved
in `outputs/validation-release-0.2.3.json`.

## 2026-11-12 published-version alignment

Both source worktrees now follow the published `shunge/arrow@0.2.2` release
commit `e1a680607adee975c55ab1ec4385da266d4deb11`. The registry package and its
SHA256 were independently verified. The four release CI jobs on Ubuntu and
Windows, using the fixed 0.10.20+65efd5b93 toolchain and official latest,
completed successfully. The README, consumer dependency and release history
now use the same version and toolchain.

The combined verifier contains 23 source checks and 15 extracted-archive
checks. It preserves the Native demo and strict test warnings from the
released workflow, and adds four-backend public API consumers, Native/JS
Iris workflows, source/core/compiler provenance and pre-compilation interface
stability checks. CI retains the released official installers, Node.js 24,
Windows MSVC initialization and weekly schedule.

The additional verification changes are included in 0.2.3. Local
validation uses the isolated Windows MSVC environment described below.

After `moon clean`, both worktrees independently passed all 23 source checks
and all 15 extracted-archive checks. Each reported 63/63 tests on all four
backends, four public API consumers, the Native demo, 128 PyArrow assertions
per Native/JS target, and both file and Iris workflows on Native and JS.
Each worktree saved its full command log in
`outputs/validation-aligned-2026-11-12.json`.

## 2026-11-12 compatibility maintenance

The official `latest` channel resolved to moon/moonrun 0.1.20261104 (940aa18),
moonc 0.10.20+65efd5b93, and core 0.10.20+65efd5b93. The Windows toolchain
was downloaded into an isolated directory and moved outside the build tree
with MSVC 14.44.35207 and Windows SDK 10.0.26100.0 before final verification.
The MSVC compiler product version is 14.44.35230.0.
The local `activate-latest.ps1` sets this process's compiler and SDK environment.
The run used `MOONBIT_NEW_NATIVE=1` and the MSVC driver, and began with
`moon clean`, `moon info` and `moon fmt`.
Its binary archive matched the official SHA256. The local test dependencies
are Python 3.13.9, Node.js 24.15.0 and PyArrow 21.0.0.

The original source passed all four backends on the previous 0.10.14
toolchain, with 63 tests per backend. The current compiler exposed deprecated
derive syntax and removed implicit JSON conversion methods. The source now
uses prefix derive attributes, explicit JSON trait calls and JSON constructors.
The current formatter also emits `Int32`/`UInt32` spellings. Comparing public
interfaces after normalizing these aliases and derive syntax produced equal
declarations. The language migrations are described in the
[November toolchain update](https://www.moonbitlang.com/updates/2026/11/05/index).

Windows Native requires MSVC-compatible C++ build tools and the Windows SDK.
The machine's existing MinGW could run the historical toolchain. The current
runtime requires the supported Windows toolchain documented in the
[Native compiler configuration](https://docs.moonbitlang.com/en/stable/toolchain/moon/package.html).

The initial local entry point contained 22 checks, including explicit builds,
four-backend public API consumers and both Native/JS Iris workflows.
That run independently extracted the generated archive and ran 14 checks.
Interface verification compares local text before and after generation,
allowing reviewed working-tree edits and normalizing Windows line endings.
It runs before type checking, which can itself refresh generated interfaces.
Failure, missing-command, timeout and interface-drift probes verified that
the entry point writes a failed report and returns a nonzero status.

All 22 checks passed after cleaning the build cache. Full command output is
saved in the ignored `outputs/validation-latest-2026-11-12.json`.
A second complete run also passed all 22 checks and the archive's 14 checks,
recorded in `outputs/validation-latest-repeat-2026-11-12.json`.

| Check | Current toolchain result |
| --- | --- |
| Four-backend check and build with `--deny-warn` | Passed |
| Four-backend tests | 63/63 on Native, JS, Wasm and Wasm-GC |
| Independent public API consumer | Passed on all four backends |
| PyArrow interoperability | 128 assertions per Native/JS target |
| Two file workflows and the full UCI Iris workflow | Passed on Native and JS |
| Interface generation, formatting and whitespace | Passed |
| Extracted Mooncakes archive | All 14 checks passed, including four-backend tests and consumers and Native/JS external workflows |

Reproduce with the verified compiler, matching core and native build tools.

```sh
moon version --all
python -m pip install -r tools/requirements-interop.txt
python tools/verify.py --report outputs/validation-latest-2026-11-12.json
```

CI now checks the fixed 0.10.20+65efd5b93 toolchain/core and official `latest`
on Ubuntu and Windows, on pushes, pull requests and weekly. Each job uploads
its validation report, including failures. The compatibility fixes have
been published in 0.2.2. All four remote CI jobs for release commit `e1a6806`
passed. This worktree's additional verification coverage and interface checks
are included in 0.2.3.

## 2026-11-12 release 0.2.2 compatibility verification

The official current stable binaries were downloaded into isolated toolchain
directories and checked against their published SHA256 values. Actual versions
were moon/moonrun 0.1.20261104 (940aa18) and moonc
0.10.20+65efd5b93, with the matching official core.

`python tools/verify.py --report outputs/validation-linux-2026-11-12.json`
passed all **18 checks** on Ubuntu 24.04 under WSL2, with GCC 13.3.0,
Python 3.12.3, Node.js 18.19.1 and PyArrow 21.0.0.

| Check | Local result |
| --- | --- |
| Four-backend warning-free check and explicit build | Passed |
| wasm / wasm-gc / js / native tests | 63/63 passed per backend |
| Native demo and independent public-API consumer | Passed |
| PyArrow interoperability | 128 assertions passed on Native and 128 on JS |
| File workflows and UCI Iris workflow | Passed |
| Generated interfaces, format and whitespace | Passed |
| Exact extracted Mooncakes archive | Four-backend check/build/tests, demo, consumer and all external workflows passed |

Windows also passed explicit builds and all 63 tests on each of js, wasm and
wasm-gc, together with the JS PyArrow assertions and file workflows. The current
Windows native toolchain requires MSVC C++ tools and the Windows SDK. This
machine has GCC, so local native validation used Linux. CI initializes MSVC
on Windows and checks both the fixed compiler and the official current stable
release on both operating systems, including weekly compatibility runs.

The new compiler rejected 18 deprecated derive declarations and 17 implicit
JSON method calls in the interoperability transport. The formatter migrated
type and parameter spellings. After normalizing Int/UInt aliases, all 130
public function signatures match the previous interfaces. The full command
reports remain in the ignored `outputs/` directory. Registry publication and
remote CI results are checked separately after this local validation.

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
