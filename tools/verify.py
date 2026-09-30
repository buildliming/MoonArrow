"""Run the source-tree release checks and keep a machine-readable local record.

Install tools/requirements-interop.txt first, then run from any directory:
    python tools/verify.py
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import importlib.metadata
import json
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
        ("node version", ["node", "--version"]),
        ("check all targets", ["moon", "check", "--target", "all", "--deny-warn"]),
        ("test all targets", ["moon", "test", "--target", "all"]),
        ("native consumer", ["moon", "run", "examples/consumer", "--target", "native"]),
        ("native interop", [python, "tools/interop.py", "--target", "native"]),
        ("js interop", [python, "tools/interop.py", "--target", "js"]),
        ("native workflow", [python, "tools/workflow.py", "--target", "native"]),
        ("js workflow", [python, "tools/workflow.py", "--target", "js"]),
        ("UCI Iris workflow", [python, "tools/iris_workflow.py", "--target", "native"]),
        ("core source count", [python, "tools/count_core.py", "--min-effective", "4001"]),
        ("public interface", ["moon", "info"]),
        ("format", ["moon", "fmt", "--check"]),
        ("interface diff", ["git", "diff", "--exit-code", "--", "*.mbti"]),
        ("whitespace diff", ["git", "diff", "--check"]),
        ("packaged source", [python, "tools/verify_package.py"]),
    ]


def run_check(name: str, command: list[str]) -> dict[str, object]:
    started = time.monotonic()
    try:
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
        return {
            "name": name,
            "command": command,
            "exit_code": result.returncode,
            "duration_seconds": round(time.monotonic() - started, 3),
            "stdout": result.stdout,
            "stderr": result.stderr,
        }
    except (OSError, subprocess.TimeoutExpired) as error:
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

    report = {
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "platform": platform.platform(),
        "python": sys.version,
        "pyarrow": pyarrow_version,
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
