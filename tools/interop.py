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


def json_nested(value):
    if isinstance(value, tuple):
        return [json_nested(v) for v in value]
    if isinstance(value, list):
        return [json_nested(v) for v in value]
    if isinstance(value, dict):
        return {k: json_nested(v) for k, v in value.items()}
    return value


def metadata_json(metadata):
    return [[k.decode("utf-8"), v.decode("utf-8")] for k, v in (metadata or {}).items()]


def normalize(schema, batches):
    fields = [{"name": f.name, "type": str(f.type), "nullable": f.nullable,
               "metadata": metadata_json(f.metadata)} for f in schema]
    result = {"schema": {"fields": fields, "metadata": metadata_json(schema.metadata)}, "batches": []}
    for batch in batches:
        columns = []
        for field, array in zip(schema, batch.columns):
            if pa.types.is_date32(field.type):
                array = array.cast(pa.int32())
            elif (pa.types.is_date64(field.type) or
                  pa.types.is_timestamp(field.type) or
                  pa.types.is_duration(field.type)):
                array = array.cast(pa.int64())
            values = []
            for scalar in array:
                value = scalar.as_py()
                if value is not None:
                    if (pa.types.is_int64(field.type) or pa.types.is_uint64(field.type) or
                        pa.types.is_date64(field.type) or pa.types.is_timestamp(field.type) or
                        pa.types.is_duration(field.type)):
                        value = str(value)
                    elif pa.types.is_float32(field.type):
                        value = str(struct.unpack("<i", struct.pack("<f", value))[0])
                    elif pa.types.is_float64(field.type):
                        value = str(struct.unpack("<q", struct.pack("<d", value))[0])
                    elif (pa.types.is_binary(field.type) or
                          pa.types.is_large_binary(field.type) or
                          pa.types.is_fixed_size_binary(field.type)) or (
                        pa.types.is_dictionary(field.type) and
                        pa.types.is_binary(field.type.value_type)
                    ):
                        value = value.hex()
                values.append(json_nested(value))
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


def numeric_case():
    types = [pa.int8(), pa.int16(), pa.uint8(), pa.uint16(),
             pa.uint32(), pa.uint64(), pa.float32()]
    values = [
        [-128, -1, None, 127],
        [-32768, -1, None, 32767],
        [0, 255, None, 1],
        [0, 65535, None, 1],
        [0, 2**32 - 1, None, 2**31 + 1],
        [0, 2**64 - 1, None, 2**53 + 1],
        [0.0, -0.0, None, 1.5],
    ]
    schema = pa.schema([pa.field(f"n{i}", typ) for i, typ in enumerate(types)])
    batch = pa.RecordBatch.from_arrays(
        [pa.array(v, type=t) for v, t in zip(values, types)], schema=schema
    )
    return schema, [batch]


def temporal_case():
    types = [pa.date32(), pa.date64(), pa.timestamp("s"),
             pa.timestamp("us", tz="UTC"), pa.timestamp("ns", tz="Asia/Shanghai"),
             pa.duration("ms"), pa.duration("ns")]
    data = [[0, 1, None, -1], [0, 86400000, None, -86400000],
            [0, 1, None, -1], [0, 123456789, None, -1],
            [0, 123456789, None, -1], [0, 1, None, -1],
            [0, 123456789, None, -1]]
    schema = pa.schema([pa.field(f"t{i}", typ) for i, typ in enumerate(types)])
    arrays = [pa.array(v, type=pa.int32() if pa.types.is_date32(t) else pa.int64()).cast(t)
              for v, t in zip(data, types)]
    return schema, [pa.RecordBatch.from_arrays(arrays, schema=schema)]


def nested_case():
    list_type = pa.list_(pa.field("item", pa.int32()))
    struct_type = pa.struct([pa.field("code", pa.int16()),
                             pa.field("label", pa.string())])
    list_struct = pa.list_(pa.field("item", struct_type))
    schema = pa.schema([pa.field("numbers", list_type),
                        pa.field("record", struct_type),
                        pa.field("records", list_struct)])
    columns = [
        pa.array([[1, None], None, [], [3]], type=list_type),
        pa.array([{"code": 1, "label": "a"}, None,
                  {"code": 2, "label": None}, {"code": -1, "label": "z"}],
                 type=struct_type),
        pa.array([[{"code": 1, "label": "x"}], None, [],
                  [{"code": 2, "label": "y"}, None]], type=list_struct),
    ]
    return schema, [pa.RecordBatch.from_arrays(columns, schema=schema)]


def dictionary_case():
    dictionary_type = pa.dictionary(pa.int32(), pa.string())
    schema = pa.schema([pa.field("category", dictionary_type)])
    words = pa.array(["red", "green", "blue"])
    first = pa.DictionaryArray.from_arrays(pa.array([0, 1, None, 0], type=pa.int32()), words)
    second = pa.DictionaryArray.from_arrays(pa.array([2, 1, 0], type=pa.int32()), words)
    return schema, [pa.RecordBatch.from_arrays([first], schema=schema),
                    pa.RecordBatch.from_arrays([second], schema=schema)]


def dictionary_replacement_case():
    typ = pa.dictionary(pa.int32(), pa.string())
    schema = pa.schema([pa.field("category", typ)])
    result = []
    for words, indices in [(["red", "green"], [0, 1, None]),
                           (["blue", "green"], [0, 1, 0])]:
        col = pa.DictionaryArray.from_arrays(pa.array(indices, type=pa.int32()),
                                              pa.array(words))
        result.append(pa.RecordBatch.from_arrays([col], schema=schema))
    return schema, result


def binary_variants_case():
    types = [pa.large_string(), pa.large_binary(), pa.binary(4)]
    values = [["", "月兔", None], [b"", b"\xff\x00", None],
              [b"abcd", None, b"\x00\x01\x02\x03"]]
    schema = pa.schema([pa.field(f"binary_{i}", typ) for i, typ in enumerate(types)])
    arrays = [pa.array(v, type=t) for v, t in zip(values, types)]
    return schema, [pa.RecordBatch.from_arrays(arrays, schema=schema)]


def fixed_list_case():
    typ = pa.list_(pa.field("item", pa.int16()), 3)
    schema = pa.schema([pa.field("triples", typ)])
    array = pa.array([[1, 2, 3], None, [None, -1, 32767]], type=typ)
    return schema, [pa.RecordBatch.from_arrays([array], schema=schema)]


def large_list_case():
    typ = pa.large_list(pa.field("item", pa.string()))
    schema = pa.schema([pa.field("words", typ)])
    array = pa.array([["moon", None], None, [], ["月兔"]], type=typ)
    return schema, [pa.RecordBatch.from_arrays([array], schema=schema)]


def map_case():
    typ = pa.map_(pa.string(), pa.int32())
    schema = pa.schema([pa.field("attrs", typ)])
    array = pa.array([[('a', 1), ('b', None)], None, [], [('x', -7)]], type=typ)
    return schema, [pa.RecordBatch.from_arrays([array], schema=schema)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--target", choices=["native", "js"], default="native")
    parser.add_argument("--fixtures-dir", type=Path, help="Optionally save oracle fixtures and MoonBit output")
    args = parser.parse_args()
    if not args.skip_build:
        subprocess.run(["moon", "build", "--target", args.target], cwd=ROOT, check=True)
    build = ROOT / "_build" / args.target / "debug" / "build" / "shunge" / "arrow" / "cmd" / "interop"
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

    schema, batches = numeric_case()
    for kind in ["stream", "file"]:
        verify(schema, batches, write_arrow(schema, batches, kind), kind, "numeric-widths")

    schema, batches = temporal_case()
    for kind in ["stream", "file"]:
        verify(schema, batches, write_arrow(schema, batches, kind), kind, "temporal")

    schema, batches = nested_case()
    for kind in ["stream", "file"]:
        verify(schema, batches, write_arrow(schema, batches, kind), kind, "nested")

    schema, batches = dictionary_case()
    for kind in ["stream", "file"]:
        verify(schema, batches, write_arrow(schema, batches, kind), kind, "dictionary")

    schema, batches = binary_variants_case()
    for kind in ["stream", "file"]:
        verify(schema, batches, write_arrow(schema, batches, kind), kind, "binary-variants")

    schema, batches = fixed_list_case()
    for kind in ["stream", "file"]:
        verify(schema, batches, write_arrow(schema, batches, kind), kind, "fixed-list")

    schema, batches = large_list_case()
    for kind in ["stream", "file"]:
        verify(schema, batches, write_arrow(schema, batches, kind), kind, "large-list")

    schema, batches = map_case()
    for kind in ["stream", "file"]:
        verify(schema, batches, write_arrow(schema, batches, kind), kind, "map")

    schema, batches = dictionary_replacement_case()
    raw = write_arrow(schema, batches, "stream")
    result = call("stream", raw)
    assert result["data"] == normalize(schema, batches), ("dictionary replacement", result)
    assert read_arrow(bytes.fromhex(result["stream"]), "stream") == normalize(schema, batches)
    assert result["file"] is None
    checks += 3

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

    unsupported = [pa.array([1, 2], type=pa.decimal128(10, 0))]
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
