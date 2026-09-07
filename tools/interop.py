"""Independent PyArrow oracle for the MoonBit IPC implementation.

Run: python tools/interop.py
The driver exchanges hex arguments with cmd/interop (small fixtures only).
No PyArrow code is involved in the MoonBit library or its production runtime.
"""
from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
import random
import struct
import subprocess

import pyarrow as pa

ROOT = Path(__file__).resolve().parents[1]
TYPES = [pa.null(), pa.bool_(), pa.int32(), pa.int64(), pa.float64(), pa.string(), pa.binary()]


def metadata_json(metadata):
    return [[k.decode("utf-8"), v.decode("utf-8")] for k, v in (metadata or {}).items()]


def normalize(schema, batches):
    fields = [{"name": f.name, "type": str(f.type), "nullable": f.nullable,
               "metadata": metadata_json(f.metadata)} for f in schema]
    result = {"schema": {"fields": fields, "metadata": metadata_json(schema.metadata)}, "batches": []}
    for batch in batches:
        columns = []
        for field, array in zip(schema, batch.columns):
            values = []
            for scalar in array:
                value = scalar.as_py()
                if value is not None:
                    if pa.types.is_int64(field.type):
                        value = str(value)
                    elif pa.types.is_float64(field.type):
                        value = str(struct.unpack("<q", struct.pack("<d", value))[0])
                    elif pa.types.is_binary(field.type):
                        value = value.hex()
                values.append(value)
            columns.append(values)
        result["batches"].append({"rows": batch.num_rows, "columns": columns})
    return result


def read_arrow(raw, kind):
    reader = pa.ipc.open_stream(raw) if kind == "stream" else pa.ipc.open_file(raw)
    batches = list(reader) if kind == "stream" else [reader.get_batch(i) for i in range(reader.num_record_batches)]
    for batch in batches:
        batch.validate(full=True)
    return normalize(reader.schema, batches)


def write_arrow(schema, batches, kind, options=None):
    sink = pa.BufferOutputStream()
    factory = pa.ipc.new_stream if kind == "stream" else pa.ipc.new_file
    with factory(sink, schema, options=options) as writer:
        for batch in batches:
            writer.write_batch(batch)
    return sink.getvalue().to_pybytes()


def generated_case(seed, count):
    rng = random.Random(seed)
    schema = pa.schema([
        pa.field("col_" + str(i), typ, metadata={b"role": b"fixture"}) for i, typ in enumerate(TYPES)
    ], metadata={"source": "PyArrow", "描述": "月兔🐇"})
    batches = []
    for size in [count, 0, min(count, 3)]:
        values = [[] for _ in TYPES]
        for i in range(size):
            values[0].append(None)
            values[1].append(rng.choice([None, False, True]))
            values[2].append(rng.choice([None, -(2**31), 2**31 - 1, rng.randrange(-999, 999)]))
            values[3].append(rng.choice([None, -(2**63), 2**63 - 1, 2**53 + 1, rng.randrange(-2**63, 2**63)]))
            values[4].append(rng.choice([None, 0.0, -0.0, math.inf, -math.inf, math.nan, rng.uniform(-1e40, 1e40)]))
            values[5].append(rng.choice([None, "", "月兔🐇", "\ufeffbom", "x\x00y", "e\u0301", "line\nquote\""]))
            values[6].append(rng.choice([None, b"", b"\xff\x00\xfe", bytes(rng.randrange(256) for _ in range(7))]))
        arrays = [pa.array(v, type=t) for v, t in zip(values, TYPES)]
        batches.append(pa.RecordBatch.from_arrays(arrays, schema=schema))
    return schema, batches


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--target", choices=["native", "js"], default="native")
    parser.add_argument("--fixtures-dir", type=Path, help="Optionally save oracle fixtures and MoonBit output")
    args = parser.parse_args()
    if not args.skip_build:
        subprocess.run(["moon", "build", "--target", args.target], cwd=ROOT, check=True)
    build = ROOT / "_build" / args.target / "debug" / "build" / "cmd" / "interop"
    if args.target == "native":
        command = [str(build / ("interop.exe" if os.name == "nt" else "interop.exe"))]
        if not Path(command[0]).exists():
            command = [str(build / "interop")]
    else:
        command = ["node", str(build / "interop.js")]

    def call(kind, raw=None):
        proc = subprocess.run(command + [kind] + ([] if raw is None else [raw.hex()]),
                              capture_output=True, text=True, encoding="utf-8", timeout=15, check=True)
        return json.loads(proc.stdout)

    checks = 0

    def verify(schema, batches, raw, kind, label):
        nonlocal checks
        result = call(kind, raw)
        assert "error" not in result, (label, result)
        expected = normalize(schema, batches)
        assert result["data"] == expected, (label, "MoonBit decoded data differs", result["data"], expected)
        for output_kind in ["stream", "file"]:
            rewritten = bytes.fromhex(result[output_kind])
            assert read_arrow(rewritten, output_kind) == expected, (label, output_kind, "PyArrow roundtrip differs")
            checks += 1
        checks += 1
        if args.fixtures_dir:
            args.fixtures_dir.mkdir(parents=True, exist_ok=True)
            (args.fixtures_dir / f"{label}.{kind}").write_bytes(raw)

    sample = call("sample")
    assert "error" not in sample, sample
    for kind in ["stream", "file"]:
        raw = bytes.fromhex(sample[kind])
        assert read_arrow(raw, kind) == sample["data"], ("MoonBit-origin sample", kind)
        checks += 1
        if args.fixtures_dir:
            args.fixtures_dir.mkdir(parents=True, exist_ok=True)
            (args.fixtures_dir / f"moonbit-sample.{kind}").write_bytes(raw)

    for seed, count in enumerate([0, 1, 7, 8, 9, 31, 63]):
        schema, batches = generated_case(seed, count)
        for kind in ["stream", "file"]:
            verify(schema, batches, write_arrow(schema, batches, kind), kind, f"random-{seed}")

    schema, batches = generated_case(123, 9)
    for version in [pa.ipc.MetadataVersion.V4, pa.ipc.MetadataVersion.V5]:
        options = pa.ipc.IpcWriteOptions(metadata_version=version, use_legacy_format=True)
        for kind in ["stream", "file"]:
            verify(schema, batches, write_arrow(schema, batches, kind, options), kind, f"legacy-{version}")

    for schema in [pa.schema([]), pa.schema([pa.field("n", pa.int64(), nullable=False)])]:
        for kind in ["stream", "file"]:
            verify(schema, [], write_arrow(schema, [], kind), kind, f"schema-only-{len(schema)}")

    # Array offsets and null bitmaps must be normalized correctly by both writers.
    array = pa.array(["skip", None, "月兔", "", None, "tail"])
    schema = pa.schema([pa.field("slice", pa.string())])
    batches = [pa.RecordBatch.from_arrays([array.slice(1, 4)], schema=schema)]
    for kind in ["stream", "file"]:
        verify(schema, batches, write_arrow(schema, batches, kind), kind, "sliced")

    unsupported = [pa.array([1, 2], type=pa.uint32()), pa.array([[1], [2]]),
                   pa.array(["a", "b"]).dictionary_encode(), pa.array([1.0, 2.0], type=pa.float32())]
    for array in unsupported:
        batch = pa.RecordBatch.from_arrays([array], names=["unsupported"])
        result = call("stream", write_arrow(batch.schema, [batch], "stream"))
        assert "error" in result, ("unsupported type accepted", array.type)
        checks += 1

    schema, batches = generated_case(999, 31)
    for codec in ["lz4", "zstd"]:
        if pa.Codec.is_available(codec):
            options = pa.ipc.IpcWriteOptions(compression=codec)
            result = call("stream", write_arrow(schema, batches, "stream", options))
            assert "error" in result, ("compressed body accepted", codec)
            checks += 1

    print(f"PASS: {checks} independent interoperability assertions; PyArrow {pa.__version__}; target={args.target}")


if __name__ == "__main__":
    main()
