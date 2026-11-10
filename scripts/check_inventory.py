#!/usr/bin/env python3
"""Validate inventory/inventory.csv (see wiki/methodology/inventory.md).

Errors (exit code 1):
- the header is not exactly the expected columns;
- an id is empty or not unique;
- area, kind or status has a value that is not allowed;
- line is not a positive integer;
- an `excluded` row has no reason, or the reason has no known prefix;
- a `todo` row has a reason (reasons are for exclusions only);
- a `modelled` row has an empty `registry`;
- the file does not exist in the Cats Effect checkout (only if the checkout exists;
  CI does not have it, so this check is skipped there), or the line is past the end.

Usage: scripts/check_inventory.py [CSV] [--ce PATH]
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path

COLUMNS = ["id", "area", "kind", "file", "line", "status", "reason", "registry"]
AREAS = {"kernel", "core", "std", "laws", "runtime"}
KINDS = {"method", "constructor", "runloop-branch", "law"}
STATUSES = {"todo", "modelled", "excluded"}
REASON_PREFIXES = ("deferred:", "platform:", "internal:", "trivial:", "no-behaviour:")
ID_RE = re.compile(r"^[A-Za-z_][\w$.<>*&!=:|+\-/~^%?@#\\]*$")


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser()
    ap.add_argument("csv", nargs="?", default=str(root / "inventory" / "inventory.csv"))
    ap.add_argument("--ce", default=str(Path.home() / "Projects" / "cats-effect"))
    args = ap.parse_args()

    path = Path(args.csv)
    ce = Path(args.ce).expanduser()
    check_files = (ce / "kernel").is_dir() and (ce / "core").is_dir()
    errors: list[str] = []
    line_counts: dict[str, int | None] = {}

    with path.open(encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        if header != COLUMNS:
            print(f"error: {path}: header is {header}, expected {COLUMNS}")
            return 1
        seen: dict[str, int] = {}
        n = 0
        for n, rec in enumerate(reader, start=2):
            where = f"{path.name}:{n}"
            if len(rec) != len(COLUMNS):
                errors.append(f"{where}: {len(rec)} fields, expected {len(COLUMNS)}")
                continue
            row = dict(zip(COLUMNS, rec))
            rid = row["id"]
            if not rid or not ID_RE.match(rid):
                errors.append(f"{where}: bad id {rid!r}")
            elif rid in seen:
                errors.append(f"{where}: duplicate id {rid} (first at line {seen[rid]})")
            else:
                seen[rid] = n
            if row["area"] not in AREAS:
                errors.append(f"{where}: bad area {row['area']!r}")
            elif rid and not rid.startswith(row["area"] + "."):
                errors.append(f"{where}: id {rid} does not start with area {row['area']}")
            if row["kind"] not in KINDS:
                errors.append(f"{where}: bad kind {row['kind']!r}")
            if not row["line"].isdigit() or int(row["line"]) < 1:
                errors.append(f"{where}: bad line {row['line']!r}")
            st, reason, reg = row["status"], row["reason"].strip(), row["registry"].strip()
            if st not in STATUSES:
                errors.append(f"{where}: bad status {st!r}")
            if st == "excluded":
                if not reason.startswith(REASON_PREFIXES):
                    errors.append(f"{where}: excluded row needs a reason with a prefix {REASON_PREFIXES}")
                elif not reason.split(":", 1)[1].strip():
                    errors.append(f"{where}: excluded row needs a justification after the prefix")
            elif reason:
                errors.append(f"{where}: reason is only for excluded rows (status {st})")
            if st == "modelled" and not reg:
                errors.append(f"{where}: modelled row needs a registry entry")
            if check_files:
                rel = row["file"]
                if rel not in line_counts:
                    src = ce / rel
                    line_counts[rel] = (
                        src.read_text(encoding="utf-8").count("\n") + 1 if src.is_file() else None
                    )
                total = line_counts[rel]
                if total is None:
                    errors.append(f"{where}: file not found in {ce}: {rel}")
                elif row["line"].isdigit() and int(row["line"]) > total:
                    errors.append(f"{where}: line {row['line']} is past the end of {rel} ({total} lines)")

    for e in errors:
        print(f"error: {e}")
    rows = len(seen)
    note = "" if check_files else " (file check skipped: no Cats Effect checkout)"
    if errors:
        print(f"FAIL: {len(errors)} error(s) in {path}{note}.")
        return 1
    print(f"OK: {rows} rows in {path}{note}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
