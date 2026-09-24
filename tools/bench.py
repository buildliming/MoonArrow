"""Reproducible native/JS IPC benchmark with sampled process RSS.

Run: python tools/bench.py --target native --output bench/native.json
The benchmark measures MoonBit codec loops; process RSS includes its runtime.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import subprocess
import time

import psutil

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=["native", "js"], required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    subprocess.run(["moon", "build", "cmd/bench", "--target", args.target],
                   cwd=ROOT, check=True)
    build = ROOT / "_build" / args.target / "debug" / "build" / "shunge" / "arrow" / "cmd" / "bench"
    if args.target == "native":
        exe = build / ("bench.exe" if os.name == "nt" else "bench")
        command = [str(exe)]
    else:
        command = ["node", str(build / "bench.js")]
    start = time.monotonic()
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, encoding="utf-8")
    child = psutil.Process(process.pid)
    peak_rss = 0
    while process.poll() is None:
        try:
            peak_rss = max(peak_rss, child.memory_info().rss)
        except psutil.NoSuchProcess:
            break
        time.sleep(0.005)
    stdout, stderr = process.communicate()
    if process.returncode:
        raise RuntimeError(f"benchmark exited {process.returncode}: {stderr}")
    cases = []
    for line in stdout.splitlines():
        label, *numbers = line.split(",")
        if label != "case" or len(numbers) != 6:
            raise RuntimeError(f"unexpected benchmark output: {line!r}")
        rows, iterations, ipc_bytes, encode_ms, decode_ms, decoded_rows = map(int, numbers)
        cases.append({
            "rows": rows, "iterations": iterations, "ipc_bytes": ipc_bytes,
            "encode_ms": encode_ms, "decode_ms": decode_ms,
            "decoded_rows": decoded_rows,
            "encode_rows_per_s": round(rows * iterations * 1000 / max(encode_ms, 1)),
            "decode_rows_per_s": round(rows * iterations * 1000 / max(decode_ms, 1)),
        })
    result = {
        "target": args.target, "platform": platform.platform(),
        "machine": platform.machine(), "processor": platform.processor(),
        "python": platform.python_version(),
        "moon": subprocess.check_output(["moon", "version"], text=True).strip(),
        "command": command, "wall_seconds": round(time.monotonic() - start, 3),
        "sampled_peak_rss_bytes": peak_rss, "rss_poll_interval_ms": 5,
        "cases": cases,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
