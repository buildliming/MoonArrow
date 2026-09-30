"""Verify the exact Mooncakes archive, independently of the source workspace."""

from __future__ import annotations

from pathlib import Path
import re
import subprocess
import sys
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    manifest = (ROOT / "moon.mod").read_text(encoding="utf-8")
    name = re.search(r'^name\s*=\s*"([^"]+)"', manifest, re.MULTILINE).group(1)
    version = re.search(r'^version\s*=\s*"([^"]+)"', manifest, re.MULTILINE).group(1)
    subprocess.run(["moon", "-C", str(ROOT), "package"], check=True)
    publish = ROOT / "_build" / "publish"
    archive = publish / f"{name.replace('/', '-')}-{version}.zip"
    with tempfile.TemporaryDirectory(prefix="package-check-", dir=publish) as directory:
        extracted = Path(directory)
        with zipfile.ZipFile(archive) as package:
            package.extractall(extracted)
        # The archive must carry its own workspace, sources and test tools.
        commands = [
            ["moon", "check", "--target", "all", "--deny-warn"],
            ["moon", "test", "--target", "all"],
            ["moon", "fmt", "--check"],
            ["moon", "run", "examples/consumer", "--target", "native"],
            [sys.executable, "tools/interop.py", "--target", "native"],
            [sys.executable, "tools/interop.py", "--target", "js"],
            [sys.executable, "tools/workflow.py", "--target", "native"],
            [sys.executable, "tools/workflow.py", "--target", "js"],
            [sys.executable, "tools/iris_workflow.py", "--target", "native"],
        ]
        for command in commands:
            print("PACKAGE RUN " + " ".join(command), flush=True)
            subprocess.run(command, cwd=extracted, check=True, timeout=300)
    print(f"PASS packaged {name}@{version}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
