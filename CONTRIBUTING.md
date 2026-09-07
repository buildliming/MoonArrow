# Development

Use a MoonBit toolchain supporting `moon.mod` and `moon.pkg`. The initial local
validation used moon 0.1.20260803; run `moon version --all` when reporting an issue.
Python and PyArrow are test-only dependencies. Node.js is needed for JS execution.

```sh
moon check --target all --deny-warn
moon test --target all
python -m pip install -r tools/requirements-interop.txt
python tools/interop.py --target native
python tools/interop.py --target js
moon info
moon fmt
git diff --check
```

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

Before publishing, review module ownership/name, generated public interfaces,
README support claims, test results and the license. The initial version is
local; no registry publication or contest submission is implied by CI passing.
