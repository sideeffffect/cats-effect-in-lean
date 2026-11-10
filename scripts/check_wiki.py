#!/usr/bin/env python3
"""Deterministic lint of the LLM wiki (see AGENTS.md and the karpathy-llm-wiki skill).

Errors (exit code 1):
- a relative markdown link in wiki/, README.md or AGENTS.md points to a missing file;
- a wiki article is not listed in wiki/index.md;
- an index entry points to a missing article;
- an article has no `> Sources:` line.

Warnings (exit code 0):
- a raw/ file is not referenced by any wiki article.

Usage: scripts/check_wiki.py [ROOT]   (default: the repository root)
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

LINK = re.compile(r"\]\(([^)\s]+?)\)")


def relative_links(text: str) -> list[str]:
    links = []
    for target in LINK.findall(text):
        if re.match(r"^[a-z][a-z0-9+.-]*:", target) or target.startswith("#"):
            continue  # URL or in-page anchor
        links.append(target.split("#", 1)[0])
    return links


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent)
    wiki = root / "wiki"
    errors: list[str] = []
    warnings: list[str] = []

    articles = sorted(p for p in wiki.glob("*/*.md"))
    checked = articles + [wiki / "index.md", wiki / "log.md", root / "README.md", root / "AGENTS.md"]

    for f in checked:
        if not f.exists():
            continue
        for target in relative_links(f.read_text(encoding="utf-8")):
            if not (f.parent / target).resolve().exists():
                errors.append(f"{f.relative_to(root)}: broken link -> {target}")

    index_text = (wiki / "index.md").read_text(encoding="utf-8")
    index_targets = set(relative_links(index_text))
    for a in articles:
        rel = a.relative_to(wiki).as_posix()
        if rel not in index_targets:
            errors.append(f"wiki/index.md: missing entry for {rel}")
        if "> Sources:" not in a.read_text(encoding="utf-8"):
            errors.append(f"{a.relative_to(root)}: no '> Sources:' line")

    nested = [p for p in wiki.glob("*/*/**/*.md")]
    for p in nested:
        errors.append(f"{p.relative_to(root)}: wiki allows one level of topic directories only")

    referenced = set()
    for a in articles:
        for target in relative_links(a.read_text(encoding="utf-8")):
            referenced.add((a.parent / target).resolve())
    for r in sorted((root / "raw").glob("*/*.md")):
        if r.resolve() not in referenced:
            warnings.append(f"{r.relative_to(root)}: not referenced by any wiki article")

    for w in warnings:
        print(f"warning: {w}")
    for e in errors:
        print(f"error: {e}")
    if errors:
        print(f"FAIL: {len(errors)} error(s), {len(warnings)} warning(s).")
        return 1
    print(f"OK: {len(articles)} articles, 0 errors, {len(warnings)} warning(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
