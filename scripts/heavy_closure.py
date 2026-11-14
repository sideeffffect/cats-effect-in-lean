#!/usr/bin/env python3
"""List the modules of the heavy proofs (decision 55, review batch 7 gap 3).

Input: the heavy roots (arguments; from `CatsEffectInLean.heavyModules`).
Output: every project module in the import closure of the roots that is not in the import
closure of the default target `CatsEffectInLean`, one per line, imports first. These are the
modules that only the heavy job builds and replays.

Fails (exit 1) when
- the roots differ from the `roots` of `lean_lib HeavyProofs` in `lakefile.lean`;
- a root or an imported project module has no source file;
- a root is in the default closure (then it is not heavy).

Usage (from the repository root):
  scripts/heavy_closure.py <root>...                 heavy modules, one per line
  scripts/heavy_closure.py --from-lakefile           same, roots from lakefile.lean
  scripts/heavy_closure.py --from-lakefile --matrix  JSON array of the heavy modules that are
                                                     not roots (CI matrix, decision 57)
  scripts/heavy_closure.py --from-lakefile --roots   the roots, one per line
  scripts/heavy_closure.py --from-lakefile --deps M  two lines: `light <default-target modules
                                                     that M needs>` and `heavy <heavy modules
                                                     that M needs, imports first, ending with M>`
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

PROJECT = "CatsEffectInLean"
IMPORT = re.compile(r"^\s*import\s+(\S+)", re.M)


def src(mod: str) -> Path:
    return Path(*mod.split(".")).with_suffix(".lean")


def imports(mod: str) -> list[str]:
    text = src(mod).read_text()
    # only the header: imports come before the first non-import command
    return [m for m in IMPORT.findall(text) if m == PROJECT or m.startswith(PROJECT + ".")]


def closure(roots: list[str], errors: list[str]) -> list[str]:
    """Project modules reachable from `roots`, in post-order (imports first)."""
    seen: set[str] = set()
    order: list[str] = []

    def visit(m: str, stack: tuple[str, ...]) -> None:
        if m in seen:
            return
        seen.add(m)
        if not src(m).is_file():
            errors.append(f"module {m} (imported via {' -> '.join(stack) or 'root'}) has no file {src(m)}")
            return
        for i in imports(m):
            visit(i, stack + (m,))
        order.append(m)

    for r in roots:
        visit(r, ())
    return order


def lakefile_roots() -> list[str]:
    text = Path("lakefile.lean").read_text()
    m = re.search(r"lean_lib\s+HeavyProofs\s+where\s+roots\s*:=\s*#\[(.*?)\]", text, re.S)
    if not m:
        return []
    return [r.strip().lstrip("`") for r in m.group(1).split(",") if r.strip()]


def main() -> int:
    args = sys.argv[1:]
    from_lakefile = "--from-lakefile" in args
    matrix = "--matrix" in args
    want_roots = "--roots" in args
    deps_of = None
    if "--deps" in args:
        i = args.index("--deps")
        deps_of = args[i + 1] if i + 1 < len(args) else ""
        args = args[:i] + args[i + 2:]
    args = [a for a in args if a not in ("--from-lakefile", "--matrix", "--roots")]
    errors: list[str] = []
    lroots = lakefile_roots()
    roots = lroots if from_lakefile else args
    if from_lakefile and args:
        errors.append(f"unexpected arguments {args}")
    if not roots:
        errors.append("no heavy roots given")
    if sorted(lroots) != sorted(roots):
        errors.append(f"lakefile HeavyProofs roots {lroots} differ from heavyModules {roots}")
    default = set(closure([PROJECT], errors))
    for r in roots:
        if r in default:
            errors.append(f"heavy root {r} is in the default target (imported by {PROJECT})")
    heavy = [m for m in closure(roots, errors) if m not in default]
    if deps_of is not None and deps_of not in heavy:
        errors.append(f"--deps: {deps_of!r} is not a heavy module")
    if errors:
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        return 1
    if deps_of is not None:
        need = closure([deps_of], errors)
        light = [m for m in need if m in default]
        hv = [m for m in need if m not in default]
        print("light " + " ".join(light))
        print("heavy " + " ".join(hv))
    elif matrix:
        print(json.dumps([m for m in heavy if m not in roots]))
    elif want_roots:
        for r in roots:
            print(r)
    else:
        for m in heavy:
            print(m)
    return 0


if __name__ == "__main__":
    sys.exit(main())
