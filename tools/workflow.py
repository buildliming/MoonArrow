"""Two small file workflows: PyArrow -> MoonBit -> PyArrow.

Run: python tools/workflow.py --target native [--output-dir DIR]
The CLI transports file bytes as argv hex, so these are integration examples,
not a large-file I/O adapter or a streaming throughput benchmark.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

import pyarrow as pa

ROOT = Path(__file__).resolve().parents[1]


def command_for(target: str) -> list[str]:
    build = ROOT / "_build" / target / "debug" / "build" / "shunge" / "arrow" / "cmd" / "interop"
    if target == "js":
        return ["node", str(build / "interop.js")]
    binary = build / ("interop.exe" if os.name == "nt" else "interop")
    return [str(binary)]


def cases() -> list[tuple[str, pa.Schema, list[pa.RecordBatch]]]:
    simple_schema = pa.schema([
        pa.field("id", pa.int64()),
        pa.field("name", pa.string()),
        pa.field("score", pa.float64()),
    ], metadata={b"source": b"workflow-simple"})
    simple = [
        pa.RecordBatch.from_arrays([
            pa.array([1, None, 3], type=pa.int64()),
            pa.array(["月兔", "skipped", None], type=pa.string()),
            pa.array([1.5, 2.5, -0.0], type=pa.float64()),
        ], schema=simple_schema),
        pa.RecordBatch.from_arrays([
            pa.array([None, 5], type=pa.int64()),
            pa.array(["skipped", "MoonBit"], type=pa.string()),
            pa.array([4.0, None], type=pa.float64()),
        ], schema=simple_schema),
    ]

    dictionary = pa.dictionary(pa.int32(), pa.string())
    details = pa.struct([pa.field("level", pa.int16()), pa.field("ok", pa.bool_())])
    nested_schema = pa.schema([
        pa.field("category", dictionary),
        pa.field("tags", pa.list_(pa.int32())),
        pa.field("details", details),
        pa.field("attrs", pa.map_(pa.string(), pa.int32())),
    ], metadata={b"source": b"workflow-nested"})
    nested = [pa.RecordBatch.from_arrays([
        pa.array(["a", None, "b", "a"], type=dictionary),
        pa.array([[1, 2], None, [], [3]], type=pa.list_(pa.int32())),
        pa.array([{"level": 1, "ok": True}, None,
                  {"level": 2, "ok": False}, {"level": None, "ok": True}],
                 type=details),
        pa.array([[('x', 7)], None, [], [('z', -1)]],
                 type=pa.map_(pa.string(), pa.int32())),
    ], schema=nested_schema)]
    return [("simple", simple_schema, simple),
            ("nested-dictionary", nested_schema, nested)]


def run(output_dir: Path, command: list[str]) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    for name, schema, batches in cases():
        source = output_dir / f"{name}-input.arrow"
        result_path = output_dir / f"{name}-filtered.arrow"
        with pa.OSFile(str(source), "wb") as sink:
            with pa.ipc.new_file(sink, schema) as writer:
                for batch in batches:
                    writer.write_batch(batch)

        mode = "filter-project-file" if name == "simple" else "filter-file"
        result = subprocess.run(
            command + [mode, source.read_bytes().hex()],
            cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
            check=True, timeout=30,
        )
        payload = json.loads(result.stdout)
        if "error" in payload:
            raise RuntimeError(f"{name}: {payload['error']}")
        result_path.write_bytes(bytes.fromhex(payload["file"]))

        with pa.memory_map(str(source), "r") as infile, pa.memory_map(str(result_path), "r") as outfile:
            original = pa.ipc.open_file(infile).read_all()
            actual = pa.ipc.open_file(outfile).read_all()
        expected = original.filter(original.column(0).is_valid())
        if name == "simple":
            expected = expected.select(["id", "name"])
        if not actual.schema.equals(expected.schema, check_metadata=True):
            raise AssertionError(f"{name}: schema or metadata changed")
        if actual.to_pylist() != expected.to_pylist():
            raise AssertionError(f"{name}: filtered rows differ")
        print(f"{name}: {original.num_rows} -> {actual.num_rows} rows; {result_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=["native", "js"], default="native")
    parser.add_argument("--output-dir", type=Path,
                        help="keep .arrow artifacts in this directory")
    args = parser.parse_args()
    subprocess.run(["moon", "build", "cmd/interop", "--target", args.target],
                   cwd=ROOT, check=True)
    command = command_for(args.target)
    if args.output_dir:
        run(args.output_dir.resolve(), command)
    else:
        with tempfile.TemporaryDirectory(prefix="moonarrow-workflow-") as scratch:
            run(Path(scratch), command)


if __name__ == "__main__":
    main()
