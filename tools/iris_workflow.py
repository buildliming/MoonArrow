"""Run the UCI Iris dataset through a PyArrow -> MoonBit -> PyArrow workflow.

Run: python tools/iris_workflow.py --target native [--output-dir DIR]
The demo uses a small fixture and transports its Arrow bytes as hex argv.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
from pathlib import Path
import subprocess
import tempfile

import pyarrow as pa
import pyarrow.compute as pc


ROOT = Path(__file__).resolve().parents[1]
DATASET = ROOT / "examples" / "iris" / "iris.csv"
FIELD_NAMES = [
    "sepal_length_cm",
    "sepal_width_cm",
    "petal_length_cm",
    "petal_width_cm",
    "species",
]
OUTPUT_FIELDS = ["sepal_length_cm", "petal_length_cm", "species"]
BATCH_ROWS = 37
MAX_HEX_ARGUMENT_LENGTH = 30000


def read_dataset() -> pa.Table:
    rows: list[list[str]] = []
    with DATASET.open(encoding="utf-8", newline="") as source:
        reader = csv.DictReader(source)
        if reader.fieldnames != FIELD_NAMES:
            raise ValueError(f"unexpected Iris CSV columns: {reader.fieldnames}")
        rows.extend([[row[name] for name in FIELD_NAMES] for row in reader])

    if len(rows) != 150:
        raise ValueError(f"expected all 150 UCI Iris observations, found {len(rows)}")
    schema = pa.schema([
        pa.field("sepal_length_cm", pa.float64(), nullable=False),
        pa.field("sepal_width_cm", pa.float64(), nullable=False),
        pa.field("petal_length_cm", pa.float64(), nullable=False),
        pa.field("petal_width_cm", pa.float64(), nullable=False),
        pa.field("species", pa.string(), nullable=False),
    ], metadata={b"source": b"UCI Iris; doi:10.24432/C56C76"})
    columns = [
        pa.array([float(row[index]) for row in rows], type=pa.float64())
        for index in range(4)
    ]
    columns.append(pa.array([row[4] for row in rows], type=pa.string()))
    return pa.Table.from_arrays(columns, schema=schema)


def command_for(target: str) -> list[str]:
    build = ROOT / "_build" / target / "debug" / "build" / "shunge" / "arrow" / "cmd" / "interop"
    if target == "js":
        return ["node", str(build / "interop.js")]
    executable = build / ("interop.exe" if os.name == "nt" else "interop")
    if not executable.exists():
        executable = build / "interop.exe"
    return [str(executable)]


def run(output_dir: Path, target: str) -> None:
    table = read_dataset()
    batches = table.to_batches(max_chunksize=BATCH_ROWS)
    if len(batches) < 2:
        raise AssertionError("the Iris source must cross multiple IPC batches")

    input_path = output_dir / "iris-input.arrow"
    output_path = output_dir / "iris-setosa-features.arrow"
    with pa.OSFile(str(input_path), "wb") as sink:
        with pa.ipc.new_file(sink, table.schema) as writer:
            for batch in batches:
                writer.write_batch(batch)

    encoded = input_path.read_bytes().hex()
    if len(encoded) > MAX_HEX_ARGUMENT_LENGTH:
        raise ValueError("Iris fixture exceeds the portable demo argument limit")
    result = subprocess.run(
        command_for(target) + ["iris-setosa", encoded],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=True,
        timeout=30,
    )
    payload = json.loads(result.stdout)
    if "error" in payload:
        raise RuntimeError(payload["error"])
    if payload["file"] is None:
        raise AssertionError("MoonBit did not return an Arrow file")

    output_bytes = bytes.fromhex(payload["file"])
    output_path.write_bytes(output_bytes)
    with pa.memory_map(str(input_path), "r") as source:
        source_reader = pa.ipc.open_file(source)
        original = source_reader.read_all()
        if source_reader.num_record_batches != len(batches):
            raise AssertionError("input batch boundaries were not preserved")
    with pa.memory_map(str(output_path), "r") as source:
        output_reader = pa.ipc.open_file(source)
        actual = output_reader.read_all()

    expected = original.filter(
        pc.equal(original.column("species"), "Iris-setosa"),
    ).select(OUTPUT_FIELDS)
    if not actual.schema.equals(expected.schema, check_metadata=True):
        raise AssertionError("MoonBit changed the projected schema or metadata")
    if actual.to_pylist() != expected.to_pylist():
        raise AssertionError("MoonBit rows differ from the PyArrow reference")
    if actual.num_rows != 50 or output_reader.num_record_batches < 2:
        raise AssertionError("expected 50 matching observations across multiple batches")

    print(
        f"UCI Iris ({table.num_rows} observations, {len(batches)} batches) -> "
        f"Iris-setosa ({actual.num_rows} rows, {output_reader.num_record_batches} batches); "
        f"PyArrow verified schema and values; output: {output_path}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=["native", "js"], default="native")
    parser.add_argument("--output-dir", type=Path,
                        help="keep the source and filtered .arrow files in this directory")
    args = parser.parse_args()
    subprocess.run(["moon", "build", "cmd/interop", "--target", args.target],
                   cwd=ROOT, check=True)
    if args.output_dir:
        output_dir = args.output_dir.resolve()
        output_dir.mkdir(parents=True, exist_ok=True)
        run(output_dir, args.target)
    else:
        with tempfile.TemporaryDirectory(prefix="moonarrow-iris-") as temporary:
            run(Path(temporary), args.target)


if __name__ == "__main__":
    main()
