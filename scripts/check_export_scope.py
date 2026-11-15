#!/usr/bin/env python3
"""Check that a `leanexport` file declares every expected constant (review batch 8, gap 4).

Usage: scripts/check_export_scope.py <export.ndjson> <names.txt>

`names.txt` lists one constant per line (from `tools/HeavyDecls.lean`, the constants of every
heavy module). The script rebuilds the names of the export (`in` records: `str` and `num`
components) and the names of its declarations (`def`, `thm`, `opaque`, `axiom`, `quot`, and the
types, constructors and recursors of `inductive` records), and fails if an expected name is
missing. It prints the counts as evidence.
"""

from __future__ import annotations

import json
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    export_path, names_path = sys.argv[1], sys.argv[2]
    names: dict[int, str] = {0: ""}
    declared: set[str] = set()
    pending: list[int] = []

    def nm(i: int) -> str:
        return names.get(i, f"<unknown name {i}>")

    with open(export_path) as f:
        for line in f:
            o = json.loads(line)
            if "in" in o:
                i = o["in"]
                if "str" in o:
                    pre, s = o["str"]["pre"], o["str"]["str"]
                else:
                    pre, s = o["num"]["pre"], str(o["num"]["i"])
                p = names.get(pre, "")
                names[i] = s if p == "" else f"{p}.{s}"
                continue
            for kind in ("def", "thm", "opaque", "axiom", "quot"):
                if kind in o and isinstance(o[kind], dict) and "name" in o[kind]:
                    pending.append(o[kind]["name"])
            if "inductive" in o:
                ind = o["inductive"]
                for key in ("types", "ctors", "recs"):
                    for t in ind.get(key, []):
                        if isinstance(t, dict) and "name" in t:
                            pending.append(t["name"])
    declared = {nm(i) for i in pending}
    with open(names_path) as f:
        expected = [l.strip() for l in f if l.strip()]
    missing = [n for n in expected if n not in declared]
    print(f"export: {len(declared)} declarations; expected heavy constants: {len(expected)}; "
          f"missing: {len(missing)}")
    if not expected:
        print("FAIL: no expected names")
        return 1
    if missing:
        for n in missing[:20]:
            print(f"missing: {n}")
        return 1
    print("OK: the export declares every heavy constant")
    return 0


if __name__ == "__main__":
    sys.exit(main())
