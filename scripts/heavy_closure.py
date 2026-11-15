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
  scripts/heavy_closure.py --from-lakefile --matrix [--groups G]  JSON array of CI matrix
                                                     entries {name, modules} (decision 57):
                                                     every module except the combining ones,
                                                     at most G modules per entry
  scripts/heavy_closure.py --from-lakefile --aggregates  the combining modules: roots that import
                                                     another module of the library (built and
                                                     replayed in the aggregate job, from the
                                                     matrix artifacts)
  scripts/heavy_closure.py --from-lakefile --roots   the roots, one per line
  scripts/heavy_closure.py --from-lakefile --lib TwinChecks ...  the same for another library
                                                     (default HeavyProofs)
  scripts/heavy_closure.py --from-lakefile --deps M...  two lines: `light <default-target
                                                     modules that M... need>` and `heavy <modules
                                                     of the library that M... need, imports
                                                     first, M... included>`
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


def lakefile_roots(lib: str = "HeavyProofs") -> list[str]:
    """The `roots` of `lean_lib <lib>` in lakefile.lean (`--` comments ignored)."""
    text = Path("lakefile.lean").read_text()
    m = re.search(r"lean_lib\s+" + re.escape(lib) + r"\s+where\s+roots\s*:=\s*#\[(.*?)\]", text, re.S)
    if not m:
        return []
    body = re.sub(r"--[^\n]*", "", m.group(1))
    return re.findall(r"`([A-Za-z0-9_.']+)", body)


def option(args: list[str], name: str) -> tuple[list[str], str | None]:
    """Remove `name <value>` from args."""
    if name not in args:
        return args, None
    i = args.index(name)
    value = args[i + 1] if i + 1 < len(args) else ""
    return args[:i] + args[i + 2:], value


def main() -> int:
    args = sys.argv[1:]
    flags = {"--from-lakefile", "--matrix", "--roots", "--aggregates"}
    from_lakefile = "--from-lakefile" in args
    matrix = "--matrix" in args
    want_roots = "--roots" in args
    want_aggr = "--aggregates" in args
    args, lib = option(args, "--lib")
    lib = lib or "HeavyProofs"
    args, groups = option(args, "--groups")
    deps_of: list[str] | None = None
    if "--deps" in args:  # all arguments after --deps are modules
        i = args.index("--deps")
        deps_of = args[i + 1:]
        args = args[:i]
    args = [a for a in args if a not in flags]
    errors: list[str] = []
    lroots = lakefile_roots(lib)
    roots = lroots if from_lakefile else args
    if from_lakefile and args:
        errors.append(f"unexpected arguments {args}")
    if not roots:
        errors.append(f"no roots for {lib}")
    if sorted(lroots) != sorted(roots):
        errors.append(f"lakefile {lib} roots {lroots} differ from the given roots {roots}")
    default = set(closure([PROJECT], errors))
    for r in roots:
        if r in default:
            errors.append(f"root {r} of {lib} is in the default target (imported by {PROJECT})")
    heavy = [m for m in closure(roots, errors) if m not in default]
    if deps_of is not None:
        if not deps_of:
            errors.append("--deps: no module given")
        for d in deps_of:
            if d not in heavy:
                errors.append(f"--deps: {d!r} is not a module of {lib}")
    group_size = 1
    if groups is not None:
        if not groups.isdigit() or int(groups) < 1:
            errors.append(f"--groups: {groups!r} is not a positive number")
        else:
            group_size = int(groups)
    if errors:
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        return 1
    # Combining modules, built in the aggregate job from the matrix artifacts: a root that imports
    # a module of the library, or any module that imports two or more modules of the library
    # directly (it combines parts; a part imports at most one shared definitions module).
    lib_set = set(heavy)

    def lib_imports(m: str) -> list[str]:
        return [i for i in imports(m) if i in lib_set]

    aggr = [m for m in heavy
            if (m in roots and lib_imports(m)) or len(lib_imports(m)) >= 2]
    if deps_of is not None:
        need = closure(deps_of, errors)
        print("light " + " ".join(m for m in need if m in default))
        print("heavy " + " ".join(m for m in need if m not in default))
    elif matrix:
        # Matrix entries: the modules except the combining ones, imports first, cut into groups
        # of at most --groups modules. A part's library dependencies are at most one shared
        # definitions module (else it would be combining), so a group rebuilds little that it
        # does not own.
        leaves = [m for m in heavy if m not in aggr]
        entries = []
        for k in range(0, len(leaves), group_size):
            part = leaves[k:k + group_size]
            label = part[0].split(".")[-1] + (f" (+{len(part) - 1})" if len(part) > 1 else "")
            entries.append({"name": label, "modules": " ".join(part)})
        print(json.dumps(entries))
    elif want_aggr:
        for r in aggr:
            print(r)
    elif want_roots:
        for r in roots:
            print(r)
    else:
        for m in heavy:
            print(m)
    return 0


if __name__ == "__main__":
    sys.exit(main())
