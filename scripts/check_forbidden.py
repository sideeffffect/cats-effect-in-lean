#!/usr/bin/env python3
"""Fail if a Lean file uses a forbidden proof escape or trust hole.

The rules are in AGENTS.md ("Prove or refute"). This check reads the source
text. Comments and string literals are ignored. It complements `lake check`
and the axiom audit, which inspect the compiled environment: they cannot see
`implemented_by`, `@[extern]` or `debug.*` options.

Usage: scripts/check_forbidden.py [ROOT]   (default: the repository root)
Exit code 1 if anything is found.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# (pattern, reason). Patterns match code with comments and strings removed.
FORBIDDEN: list[tuple[str, str]] = [
    (r"\bsorry\b", "unfinished proof"),
    (r"\bsorryAx\b", "unfinished proof (the axiom behind sorry; user decision Q2, 2026-11-10)"),
    (r"\badmit\b", "unfinished proof"),
    (r"\bnative_decide\b", "trusts the compiler (adds an axiom)"),
    (r"\bbv_decide\b", "trusts an external SAT certificate path"),
    (r"\bofReduceBool\b", "trusts the compiler"),
    (r"\breduceBool\b", "trusts the compiler"),
    (r"\btrustCompiler\b", "trusts the compiler"),
    (r"\bimplemented_by\b", "runtime code differs from the logic"),
    (r"@\[\s*extern\b|\bextern\s+\"", "runtime code outside the logic"),
    (r"(?m)^\s*(?:@\[[^\]]*\]\s*)?(?:(?:private|protected|noncomputable|unsafe)\s+)*axiom\s",
     "new axiom"),
    (r"\bdebug\.\w+", "debug option (e.g. debug.skipKernelTC)"),
]

SKIP_DIRS = {".lake", ".git", "node_modules"}


def strip_comments_and_strings(src: str) -> str:
    """Replace comments and string/char literals with spaces. Keep newlines,
    so line numbers stay correct. Lean block comments nest."""
    out: list[str] = []
    i, n, depth = 0, len(src), 0
    while i < n:
        c = src[i]
        two = src[i:i + 2]
        if depth > 0:
            if two == "/-":
                depth += 1
                out.append("  ")
                i += 2
            elif two == "-/":
                depth -= 1
                out.append("  ")
                i += 2
            else:
                out.append("\n" if c == "\n" else " ")
                i += 1
        elif two == "/-":
            depth = 1
            out.append("  ")
            i += 2
        elif two == "--":
            while i < n and src[i] != "\n":
                out.append(" ")
                i += 1
        elif c == '"':
            out.append(" ")
            i += 1
            while i < n and src[i] != '"':
                if src[i] == "\\" and i + 1 < n:
                    out.append("  ")
                    i += 2
                    continue
                out.append("\n" if src[i] == "\n" else " ")
                i += 1
            out.append(" ")
            i += 1
        elif c == "'" and re.match(r"'(?:\\.[^']*|[^'\\])'", src[i:i + 12]):
            # character literal such as 'a' or '\n' (not a prime in a name)
            m = re.match(r"'(?:\\.[^']*|[^'\\])'", src[i:i + 12])
            assert m
            out.append(" " * len(m.group(0)))
            i += len(m.group(0))
        else:
            out.append(c)
            i += 1
    return "".join(out)


def lean_files(root: Path) -> list[Path]:
    return sorted(
        p for p in root.rglob("*.lean")
        if not any(part in SKIP_DIRS for part in p.relative_to(root).parts)
    )


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent)
    found = 0
    files = lean_files(root)
    for path in files:
        code = strip_comments_and_strings(path.read_text(encoding="utf-8"))
        for pattern, reason in FORBIDDEN:
            for m in re.finditer(pattern, code):
                line = code.count("\n", 0, m.start()) + 1
                rel = path.relative_to(root)
                print(f"{rel}:{line}: forbidden `{m.group(0).strip()}` ({reason})")
                found += 1
    if found:
        print(f"FAIL: {found} forbidden use(s) in {len(files)} Lean file(s). See AGENTS.md.")
        return 1
    print(f"OK: no forbidden constructs in {len(files)} Lean file(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
