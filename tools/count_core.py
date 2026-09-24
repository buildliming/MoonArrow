"""Count hand-written production MoonBit lines with a stable, auditable rule.

Run from any directory: python tools/count_core.py [--json]
This counts nonempty lines whose first nonspace characters are not //.
It intentionally reports a source-line metric, not AST statements.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED_DIRS = {"_build", "target", "cmd", "examples", "bench", ".mooncakes"}


def source_files() -> list[Path]:
    return sorted(
        p for p in ROOT.rglob("*.mbt")
        if not any(part in EXCLUDED_DIRS or part.startswith(".") for part in p.relative_to(ROOT).parts[:-1])
        and not p.name.endswith(("_test.mbt", "_wbtest.mbt"))
    )


def count(path: Path) -> dict[str, int | str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    return {
        "file": path.relative_to(ROOT).as_posix(),
        "physical": len(lines),
        "effective": sum(bool(s := line.strip()) and not s.startswith("//") for line in lines),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="machine-readable report")
    args = parser.parse_args()
    files = [count(p) for p in source_files()]
    total = {
        "physical": sum(int(f["physical"]) for f in files),
        "effective": sum(int(f["effective"]) for f in files),
    }
    if args.json:
        print(json.dumps({"files": files, "total": total}, ensure_ascii=False, indent=2))
    else:
        for item in files:
            print(f"{item['file']:32} {item['physical']:5} {item['effective']:5}")
        print(f"{'TOTAL':32} {total['physical']:5} {total['effective']:5}")


if __name__ == "__main__":
    main()
