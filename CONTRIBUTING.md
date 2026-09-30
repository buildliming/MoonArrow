# Development

Use MoonBit 0.10.14 (`moonc 0.10.14+7d59c7ec9`, moon 0.1.20260920), the
fixed toolchain/core version in CI. Earlier local records used 0.10.11;
run `moon version --all` when reporting an issue.
Python and PyArrow are test-only dependencies. Node.js is needed for JS execution.
The repository is a two-member `moon.work` workspace: the library and an
independent consumer using its public API. Run commands from the workspace root.

```sh
moon check --target all --deny-warn
moon test --target all
python -m pip install -r tools/requirements-interop.txt
python tools/interop.py --target native
python tools/interop.py --target js
python tools/workflow.py --target native
moon run examples/consumer --target native
python tools/count_core.py --min-effective 4001
moon info
moon fmt
moon fmt --check
git diff --check
```

For a complete source-tree check, run `python tools/verify.py` after installing
`tools/requirements-interop.txt`. It runs the tests, interoperability checks,
workflows, consumer, interface and format checks, and validates the extracted
Mooncakes archive with the same backend tests and external workflows. It records command output,
versions and exit codes in the ignored `outputs/validation.json`. The script
stops on the first failure and writes the partial report before returning a
nonzero exit status. Benchmarks remain separate because their timings require
a controlled local environment.

To check only the publishable archive, run `python tools/verify_package.py`.
The temporary extraction stays under `_build/publish` and is removed after
the run. This check does not access the registry or upload a package.

For a new Arrow type, update the public data model, schema codec, buffer layout,
malformed-input checks, independent PyArrow fixtures and support matrix together.
Use stable assertions for decoded values. For floats, compare bit patterns when
testing serialization. Include externally produced inputs, not only self-roundtrips.
Current `moon test` includes documentation tests; `--doc` is deprecated.

The root package contains production code. `cmd/main` is the small runnable demo;
`cmd/interop` is a hex-based test transport. `_test.mbt` files exercise public APIs;
`malformed_wbtest.mbt` exercises malformed internal layouts. `tools/interop.py`
creates deterministic PyArrow cases and checks both decoding and re-encoding.
`--fixtures-dir PATH` optionally saves input fixtures under a local output path.
`tools/workflow.py` creates two real `.arrow` file examples, but its CLI sends
small file contents as hex arguments. `tools/bench.py` requires
`tools/requirements-bench.txt`, reports debug-build Native/JS codec timing and
sampled RSS, and should run outside normal CI. `tools/count_core.py` excludes
tests, commands, examples and generated code; the CI threshold is 4001
nonblank/non-`//` production lines.

Before publishing, review module ownership/name, generated public interfaces,
README support claims, test results and the license. Use `moon publish --dry-run`
from the **library member** to validate packaged source before `moon publish`.
Registry publication and
contest submission are separate actions; CI passing does not perform either.
