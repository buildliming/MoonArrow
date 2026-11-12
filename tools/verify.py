"""Run the source-tree release checks and keep a machine-readable local record.

Install tools/requirements-interop.txt first, then run from any directory:
    python tools/verify.py
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]


def checks() -> list[tuple[str, list[str]]]:
    python = sys.executable
    return [
        ("moon version", ["moon", "version", "--all"]),
        ("source revision", ["git", "rev-parse", "HEAD"]),
        ("source changes", ["git", "status", "--porcelain"]),
        ("node version", ["node", "--version"]),
        ("public interface", ["moon", "info"]),
        ("check all targets", ["moon", "check", "--target", "all", "--deny-warn"]),
        ("build all targets", ["moon", "build", "--target", "all", "--deny-warn"]),
        ("test all targets", ["moon", "test", "--target", "all", "--deny-warn"]),
        ("native demo", ["moon", "run", "cmd/main", "--target", "native"]),
        ("native consumer", ["moon", "run", "examples/consumer", "--target", "native"]),
        ("js consumer", ["moon", "run", "examples/consumer", "--target", "js"]),
        ("wasm consumer", ["moon", "run", "examples/consumer", "--target", "wasm"]),
        ("wasm-gc consumer", ["moon", "run", "examples/consumer", "--target", "wasm-gc"]),
        ("native interop", [python, "tools/interop.py", "--target", "native"]),
        ("js interop", [python, "tools/interop.py", "--target", "js"]),
        ("native workflow", [python, "tools/workflow.py", "--target", "native"]),
        ("js workflow", [python, "tools/workflow.py", "--target", "js"]),
        ("native UCI Iris workflow", [python, "tools/iris_workflow.py", "--target", "native"]),
        ("js UCI Iris workflow", [python, "tools/iris_workflow.py", "--target", "js"]),
        ("core source count", [python, "tools/count_core.py", "--min-effective", "4001"]),
        ("format", ["moon", "fmt", "--check"]),
        ("whitespace diff", ["git", "diff", "--check"]),
        ("packaged source", [python, "tools/verify_package.py"]),
    ]


def interface_snapshot() -> dict[str, str]:
    result = subprocess.run(
        ["git", "ls-files", "-z", "--", "*.mbti"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=30,
        check=True,
    )
    return {
        path: (ROOT / path).read_text(encoding="utf-8")
        for path in result.stdout.split("\0")
        if path
    }


def run_check(name: str, command: list[str]) -> dict[str, object]:
    started = time.monotonic()
    try:
        interfaces_before = interface_snapshot() if name == "public interface" else None
        result = subprocess.run(
            command,
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=300,
            check=False,
        )
        if interfaces_before is not None and result.returncode == 0:
            interfaces_after = interface_snapshot()
            changed = sorted(
                path for path in interfaces_before.keys() | interfaces_after.keys()
                if interfaces_before.get(path) != interfaces_after.get(path)
            )
            if changed:
                result.returncode = 1
                result.stderr += (
                    "\nPublic interfaces changed during moon info:\n"
                    + "\n".join(changed)
                    + "\n"
                )
        return {
            "name": name,
            "command": command,
            "exit_code": result.returncode,
            "duration_seconds": round(time.monotonic() - started, 3),
            "stdout": result.stdout,
            "stderr": result.stderr,
        }
    except (OSError, subprocess.TimeoutExpired, subprocess.CalledProcessError) as error:
        return {
            "name": name,
            "command": command,
            "exit_code": None,
            "duration_seconds": round(time.monotonic() - started, 3),
            "error": str(error),
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--report",
        type=Path,
        default=Path("outputs/validation.json"),
        help="JSON report path, relative to the repository root",
    )
    args = parser.parse_args()
    try:
        pyarrow_version = importlib.metadata.version("pyarrow")
    except importlib.metadata.PackageNotFoundError:
        parser.error("PyArrow is required; install tools/requirements-interop.txt")

    moon_home = Path(os.environ.get("MOON_HOME", Path.home() / ".moon"))
    core_manifest = moon_home / "lib" / "core" / "moon.mod"
    core_record = {"path": str(core_manifest)}
    try:
        core_record["contents"] = core_manifest.read_text(encoding="utf-8")
    except OSError as error:
        core_record["error"] = str(error)
    report = {
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "platform": platform.platform(),
        "python": sys.version,
        "pyarrow": pyarrow_version,
        "native_environment": {
            key: os.environ.get(key)
            for key in ("MOON_CC", "MOON_AR", "CC", "MOONBIT_NEW_NATIVE")
        },
        "core_manifest": core_record,
        "checks": [],
    }
    for name, command in checks():
        print(f"RUN {name}", flush=True)
        result = run_check(name, command)
        report["checks"].append(result)
        if result["exit_code"] != 0:
            print(result.get("stdout", ""), end="", file=sys.stderr)
            print(result.get("stderr", result.get("error", "")), end="", file=sys.stderr)
            print(f"FAIL {name}", file=sys.stderr)
            break
        print(f"PASS {name} ({result['duration_seconds']}s)", flush=True)

    report["finished_utc"] = datetime.now(timezone.utc).isoformat()
    report["passed"] = len(report["checks"]) == len(checks()) and all(
        item["exit_code"] == 0 for item in report["checks"]
    )
    output = args.report if args.report.is_absolute() else ROOT / args.report
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Report: {output}")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
