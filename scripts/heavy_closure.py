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

Usage: scripts/heavy_closure.py <root>...   (from the repository root)
"""

from __future__ import annotations

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
    roots = sys.argv[1:]
    errors: list[str] = []
    if not roots:
        errors.append("no heavy roots given")
    lroots = lakefile_roots()
    if sorted(lroots) != sorted(roots):
        errors.append(f"lakefile HeavyProofs roots {lroots} differ from heavyModules {roots}")
    default = set(closure([PROJECT], errors))
    for r in roots:
        if r in default:
            errors.append(f"heavy root {r} is in the default target (imported by {PROJECT})")
    heavy = [m for m in closure(roots, errors) if m not in default]
    if errors:
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        return 1
    for m in heavy:
        print(m)
    return 0


if __name__ == "__main__":
    sys.exit(main())
