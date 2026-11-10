#!/usr/bin/env python3
"""Generate inventory/inventory.csv from the Cats Effect v3.7.1 Scala sources.

One row per item in scope (see wiki/methodology/inventory.md):
- kernel, std, core: each def / val that is a member of a named class, trait or object;
- core: each IO and SyncIO ADT constructor (tag order) and each IOFiber.runLoop
  (and SyncIO interpreter) branch on the constructor tag;
- laws: each law def in laws/shared/.../*Laws.scala;
- runtime (unsafe/**): rows start `excluded` with reason `deferred: phase 9`.

The scanner is a line/brace scanner, not a Scala parser. It removes comments and
string literals, then tracks a stack of brace and paren frames. A `{` that comes
after a `class`/`trait`/`object` header opens a template frame. Defs and vals are
recorded only when the innermost frame is a template (so local defs, and members
of anonymous classes, are not rows). Output is deterministic: files are sorted,
rows keep source order inside a file.

Usage: scripts/gen_inventory.py [--ce PATH] [--out PATH]
Default CE path: ~/Projects/cats-effect (must be at tag v3.7.1).
"""

from __future__ import annotations

import argparse
import csv
import re
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

PINNED_COMMIT = "eb0cc258fc732fc37f22f117c2e81d5554d67024"
COLUMNS = ["id", "area", "kind", "file", "line", "status", "reason", "registry"]

# --------------------------------------------------------------------------
# Lexing: blank out comments and string/char literals, keep offsets and newlines.
# --------------------------------------------------------------------------


def strip_comments_and_strings(text: str) -> str:
    out = list(text)
    n = len(text)
    i = 0

    def blank(a: int, b: int) -> None:
        for k in range(a, min(b, n)):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            j = n if j < 0 else j
            blank(i, j)
            i = j
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            depth, j = 1, i + 2
            while j < n and depth > 0:  # Scala block comments nest
                if text.startswith("/*", j):
                    depth, j = depth + 1, j + 2
                elif text.startswith("*/", j):
                    depth, j = depth - 1, j + 2
                else:
                    j += 1
            blank(i, j)
            i = j
        elif text.startswith('"""', i):
            j = text.find('"""', i + 3)
            j = n if j < 0 else j + 3
            while j < n and text[j] == '"':  # """...""""" edge case
                j += 1
            blank(i, j)
            i = j
        elif c == '"':
            j = i + 1
            while j < n and text[j] != '"' and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            blank(i, j + 1)
            i = j + 1
        elif c == "'":
            # char literal 'x' or '\n' or '\u0000'; leave symbol-like quotes alone
            m = re.match(r"'(\\u[0-9a-fA-F]{4}|\\.|[^\\'\n])'", text[i:])
            if m:
                blank(i, i + m.end())
                i += m.end()
            else:
                i += 1
        else:
            i += 1
    return "".join(out)


TOKEN = re.compile(
    r"""
    (?P<ident>`[^`\n]+`|[A-Za-z_$][\w$]*(?:_[!#%&*+\-/:<=>?@\\^|~]+)?)
  | (?P<op>[!#%&*+\-/:<=>?@\\^|~]+)
  | (?P<open>[{(\[])
  | (?P<close>[})\]])
  | (?P<num>-?\d+)
  | (?P<other>[;,.])
    """,
    re.VERBOSE,
)

TEMPLATE_KW = {"class", "trait", "object"}

# --------------------------------------------------------------------------
# Scanner
# --------------------------------------------------------------------------


@dataclass
class Frame:
    kind: str  # "template" | "block" | "paren"
    name: str | None = None
    local: bool = False  # inside a def body or an expression
    case: bool = False  # template of a `case class` / `case object`
    private: bool = False
    line: int = 0
    tag: int | None = None  # `def tag = N` inside this template
    path: tuple[str, ...] = ()
    tkw: str = ""  # "class" | "trait" | "object"


@dataclass
class Member:
    path: tuple[str, ...]  # enclosing template names
    name: str
    kw: str  # "def" | "val"
    line: int
    private: bool
    deprecated: bool
    parent_private: bool
    parent_case: bool
    parent_kw: str


@dataclass
class CaseTemplate:
    path: tuple[str, ...]  # enclosing template names
    name: str
    line: int
    private: bool
    tag: int | None


@dataclass
class Scan:
    members: list[Member] = field(default_factory=list)
    cases: list[CaseTemplate] = field(default_factory=list)


PRIVATE_RE = re.compile(r"\b(private|protected)\b")


def line_starts(text: str) -> list[int]:
    starts = [0]
    for i, ch in enumerate(text):
        if ch == "\n":
            starts.append(i + 1)
    return starts


def scan(text: str) -> Scan:
    clean = strip_comments_and_strings(text)
    starts = line_starts(clean)
    raw_lines = text.split("\n")
    clean_lines = clean.split("\n")

    def lineno(pos: int) -> int:
        lo, hi = 0, len(starts) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if starts[mid] <= pos:
                lo = mid
            else:
                hi = mid - 1
        return lo + 1

    def modifiers_before(pos: int) -> str:
        ln = lineno(pos)
        return clean[starts[ln - 1] : pos]

    def is_deprecated(line: int) -> bool:
        # look at the def line and up to 3 lines above that hold only annotations
        if "@deprecated" in clean_lines[line - 1]:
            return True
        k = line - 2
        while k >= 0 and line - 2 - k < 3:
            s = clean_lines[k].strip()
            if s.startswith("@"):
                if s.startswith("@deprecated"):
                    return True
                k -= 1
                continue
            if s == "" and raw_lines[k].strip().startswith(("//", "*", "/*")):
                k -= 1
                continue
            break
        return False

    res = Scan()
    stack: list[Frame] = [Frame(kind="template", name=None, line=0)]
    pending: dict | None = None  # template header waiting for its `{`
    tokens = list(TOKEN.finditer(clean))
    i = 0
    while i < len(tokens):
        t = tokens[i]
        kind = t.lastgroup
        val = t.group()
        top = stack[-1]
        if kind == "open":
            if val == "{":
                if pending is not None and pending["depth"] == len(stack) and top.kind != "paren":
                    stack.append(
                        Frame(
                            kind="template",
                            name=pending["name"],
                            local=top.local or top.kind != "template",
                            case=pending["case"],
                            private=pending["private"],
                            line=pending["line"],
                            path=top.path + ((top.name,) if top.name else ()),
                            tkw=pending["tkw"],
                        )
                    )
                    pending = None
                else:
                    stack.append(Frame(kind="block", local=True, path=top.path))
            else:
                stack.append(Frame(kind="paren", local=top.local, path=top.path))
        elif kind == "close":
            if len(stack) > 1:
                fr = stack.pop()
                if fr.kind == "template" and fr.case and not fr.local:
                    res.cases.append(
                        CaseTemplate(fr.path, fr.name or "?", fr.line, fr.private, fr.tag)
                    )
            if pending is not None and pending["depth"] > len(stack):
                flush_pending(res, pending)
                pending = None
        elif kind == "ident" and top.kind != "paren":
            if val in TEMPLATE_KW or val == "def" or val == "val" or val == "type" or val == "var":
                if pending is not None and pending["depth"] == len(stack):
                    # previous header had no body
                    flush_pending(res, pending)
                    pending = None
            if val in TEMPLATE_KW and i + 1 < len(tokens):
                nxt = tokens[i + 1]
                if nxt.lastgroup == "ident" and nxt.group() not in ("extends",):
                    name = nxt.group()
                    mods = modifiers_before(t.start())
                    is_case = bool(re.search(r"\bcase\s*$", mods))
                    if val == "object" and re.search(r"\bpackage\s*$", mods):
                        is_case = False
                    pending = {
                        "name": name.strip("`"),
                        "depth": len(stack),
                        "case": is_case,
                        "private": bool(PRIVATE_RE.search(mods)),
                        "line": lineno(t.start()),
                        "parent": top,
                        "tkw": val,
                    }
                    i += 2
                    continue
            elif val in ("def", "val") and top.kind == "template" and i + 1 < len(tokens):
                nxt = tokens[i + 1]
                if nxt.lastgroup in ("ident", "op"):
                    name = nxt.group().strip("`")
                    line = lineno(t.start())
                    mods = modifiers_before(t.start())
                    # `def tag = N` inside an ADT case template
                    if val == "def" and name == "tag" and top.case:
                        m = re.match(r"\s*(?::\s*Byte\s*)?=\s*(-?\d+)", clean[nxt.end() :])
                        if m:
                            top.tag = int(m.group(1))
                    if not top.local and top.name is not None:
                        res.members.append(
                            Member(
                                path=top.path + (top.name,),
                                name=name,
                                kw=val,
                                line=line,
                                private=bool(PRIVATE_RE.search(mods)),
                                deprecated=is_deprecated(line),
                                parent_private=top.private,
                                parent_case=top.case,
                                parent_kw=top.tkw,
                            )
                        )
                    i += 2
                    continue
        i += 1
    if pending is not None:
        flush_pending(res, pending)
    return res


def flush_pending(res: Scan, pending: dict) -> None:
    """A case class / case object header without a body is still a constructor."""
    parent: Frame = pending["parent"]
    if pending["case"] and parent.kind == "template" and not parent.local:
        res.cases.append(
            CaseTemplate(
                parent.path + ((parent.name,) if parent.name else ()),
                pending["name"],
                pending["line"],
                pending["private"],
                None,
            )
        )


# --------------------------------------------------------------------------
# Interpreter branches: `(cur0.tag: @switch) match { case N => ... }`
# --------------------------------------------------------------------------


def find_def_span(clean: str, name: str) -> tuple[int, int] | None:
    m = re.search(r"\bdef\s+" + re.escape(name) + r"\b", clean)
    if not m:
        return None
    # skip the parameter list: the body brace is the first `{` after `=`
    eq = clean.find("=", m.end())
    j = clean.find("{", eq)
    depth, k = 0, j
    while k < len(clean):
        if clean[k] == "{":
            depth += 1
        elif clean[k] == "}":
            depth -= 1
            if depth == 0:
                return (m.start(), k)
        k += 1
    return None


def match_cases(clean: str, start: int, end: int, scrutinee: str) -> list[tuple[int, str, int, int]]:  # noqa: E501
    """Return (match_brace, case_label, case_pos, next_case_pos) for the first
    `(scrutinee.tag: @switch) match {` in [start, end)."""
    m = re.compile(r"\(\s*" + re.escape(scrutinee) + r"\.tag\s*:\s*@switch\s*\)\s*match\s*\{").search(
        clean, start, end
    )
    if not m:
        return []
    brace = m.end() - 1
    depth, k = 0, brace
    out: list[tuple[str, int]] = []
    case_re = re.compile(r"\bcase\s+(-?\d+|_)\s*=>")
    while k < end:
        ch = clean[k]
        if ch in "{([":
            depth += 1
        elif ch in "})]":
            depth -= 1
            if depth == 0:
                break
        elif depth == 1 and ch == "c":
            cm = case_re.match(clean, k)
            if cm and (k == 0 or not (clean[k - 1].isalnum() or clean[k - 1] == "_")):
                out.append((cm.group(1), k))
        k += 1
    close = k
    result = []
    for idx, (label, pos) in enumerate(out):
        nxt = out[idx + 1][1] if idx + 1 < len(out) else close
        result.append((brace, label, pos, nxt))
    return result


# --------------------------------------------------------------------------
# Scope rules
# --------------------------------------------------------------------------

PLATFORM_ONLY = ("/js/", "/native/", "/js-native/")
JVM_DIRS = ("/jvm/", "/jvm-native/")

CORE_MODEL_FILES = {
    "IO.scala",
    "IOFiber.scala",
    "SyncIO.scala",
    "IODeferred.scala",
    "IOLocal.scala",
    "ContState.scala",
    "LiftIO.scala",
    "IOPlatform.scala",
    "IOCompanionPlatform.scala",
    "IOCompanionMultithreadedPlatform.scala",
    "SyncIOCompanionPlatform.scala",
    "IOFiberPlatform.scala",
    "IOLocalPlatform.scala",
    "ByteStack.scala",
    "ArrayStack.scala",
    "CallbackStack.scala",
}
CORE_TRIVIAL = {"implicits.scala", "package.scala"}  # plus syntax/** and instances/**


def module_of(rel: str) -> tuple[str, str, str]:
    """Return (module, platform_dir, package_rel) for a source path."""
    m = re.match(r"(kernel|core|std|laws)/([\w-]+)/src/main/scala/cats/effect/(.*)$", rel)
    if not m:
        raise ValueError(rel)
    return m.group(1), m.group(2), m.group(3)


def file_rule(rel: str) -> tuple[str, str, str]:
    """Return (area, default status, default reason) for a file."""
    module, plat, pkg = module_of(rel)
    platform_only = plat in ("js", "native", "js-native")
    if module == "core" and "/unsafe/" in "/" + pkg:
        if platform_only:
            return "runtime", "excluded", f"platform: {plat}-only runtime; JVM is the target platform"
        return "runtime", "excluded", "deferred: phase 9 (runtime/scheduler, needs a memory model)"
    area = module
    if platform_only:
        return area, "excluded", f"platform: {plat}-only source; JVM is the target platform"
    base = pkg.rsplit("/", 1)[-1]
    if pkg.startswith(("kernel/syntax/", "std/syntax/", "syntax/")):
        return area, "excluded", "trivial: syntax extension that forwards to the typeclass method"
    if module == "core":
        if pkg.startswith("instances/") or base in CORE_TRIVIAL:
            return area, "excluded", "trivial: re-export of instances or syntax"
        if base in CORE_MODEL_FILES and "/" not in pkg:
            return area, "todo", ""
        return area, "excluded", "deferred: phase 9 (app, tracing, metrics or runtime support, not the IO semantics)"
    return area, "todo", ""


def id_prefix(rel: str, area: str) -> str:
    module, plat, pkg = module_of(rel)
    parts = pkg.split("/")[:-1]
    # drop the module's own package (cats.effect.kernel / cats.effect.std / cats.effect.laws)
    if parts and parts[0] == module:
        parts = parts[1:]
    # js / native sources get a platform segment, so that JVM rows keep the plain ids
    if plat in ("js", "native", "js-native"):
        parts = [plat] + parts
    if area == "runtime":
        parts = [p for p in parts if p != "unsafe"]
    return ".".join([area] + parts)


# --------------------------------------------------------------------------
# Row building
# --------------------------------------------------------------------------


@dataclass
class Row:
    id: str
    area: str
    kind: str
    file: str
    line: int
    status: str
    reason: str
    registry: str = ""


# private defs that are interpreters in their own right (twins of the run loop)
KEEP_PRIVATE = {
    "kernel.Resource.fold",
    "core.SyncStep.interpret",
}

_T = r"(?:OptionT|EitherT|IorT|Kleisli|WriterT|StateT|ReaderWriterStateT)"
# instance classes such as `OptionTMonadCancel`, `KleisliAsync`
TRANSFORMER_TEMPLATE = re.compile(r"^" + _T + r"[A-Z]")
# instance definitions such as `asyncForWriterT`, `catsEitherTLiftIO`, `catsIndexedStateTRandom`
TRANSFORMER_INSTANCE = re.compile(r"For(?:Indexed)?" + _T + r"$|^cats(?:Indexed)?" + _T)


def tag_name(c: CaseTemplate, owner: str) -> str:
    # nested internal constructors keep their owner: IOCont.Get, Uncancelable.UnmaskRunLoop
    rest = [p for p in c.path[c.path.index(owner) + 1 :]] if owner in c.path else []
    return ".".join(rest + [c.name])


def tag_sort_key(tag: int | None) -> tuple[int, int]:
    return (1, 0) if tag is None or tag < 0 else (0, tag)


def member_rows(rel: str, sc: Scan, area: str, status: str, reason: str) -> list[Row]:
    rows: list[Row] = []
    prefix = id_prefix(rel, area)
    module, _, pkg = module_of(rel)
    base = pkg.rsplit("/", 1)[-1]
    is_laws = module == "laws" and base.endswith("Laws.scala")
    adt_owner = {"IO.scala": "IO", "SyncIO.scala": "SyncIO"}.get(base) if module == "core" else None
    for m in sc.members:
        # members of tagged ADT constructors (`def tag`, `toString`) are covered by the constructor row
        if adt_owner and m.parent_case and adt_owner in m.path:
            continue
        ident = ".".join([prefix] + list(m.path) + [m.name])
        kind = "method"
        st, rs = status, reason
        if is_laws and st == "todo":
            if (
                m.path == (base[: -len(".scala")],)
                and m.parent_kw == "trait"
                and m.kw == "def"
                and not m.private
                and m.name != "F"
            ):
                kind = "law"
            else:
                st, rs = "excluded", "trivial: law-trait plumbing (instance parameter or factory), not a law"
        if st == "todo":
            if m.private and base == "IOFiber.scala":
                pass  # IOFiber internals are the run loop we mirror
            elif m.private and ident in KEEP_PRIVATE:
                pass  # private interpreter that public methods run on
            elif m.private:
                st, rs = "excluded", "internal: private helper; modelled as part of its public caller"
            elif m.name == "this":
                st, rs = "excluded", "trivial: auxiliary constructor"
            elif any(TRANSFORMER_TEMPLATE.match(x) for x in m.path) or TRANSFORMER_INSTANCE.search(m.name):
                st, rs = "excluded", (
                    "deferred: monad-transformer instance (OptionT, EitherT, Kleisli, ...); "
                    "after IO and the generic derived combinators"
                )
            elif m.name == "toString":
                st, rs = "excluded", "no-behaviour: string rendering only"
            elif m.deprecated:
                st, rs = "excluded", "trivial: @deprecated binary-compatibility shim; the current API has its own row"
        rows.append(Row(ident, area, kind, rel, m.line, st, rs))
    # ADT constructors
    if adt_owner:
        tagged = [c for c in sc.cases if adt_owner in c.path and c.tag is not None]
        for c in sorted(tagged, key=lambda c: tag_sort_key(c.tag)):
            rows.append(
                Row(f"{prefix}.{adt_owner}.tag.{tag_name(c, adt_owner)}", area, "constructor", rel, c.line, status, reason)
            )
    elif module == "kernel" and status == "todo":
        for c in sc.cases:
            if not c.private and c.path and c.path[-1] in ("Outcome", "Resource", "ExitCase"):
                rows.append(
                    Row(".".join([prefix] + list(c.path) + [c.name]), area, "constructor", rel, c.line, status, reason)
                )
    return rows


def runloop_rows(rel: str, text: str, sc: Scan, area: str, owner: str, fn: str, cls: str) -> list[Row]:
    """Rows for each `case N =>` of the tag switch in def `fn`, plus the fast-path
    sub-switches (e.g. Map over Pure) one level down."""
    clean = strip_comments_and_strings(text)
    span = find_def_span(clean, fn)
    if span is None:
        raise SystemExit(f"{rel}: def {fn} not found")
    tags = {c.tag: tag_name(c, owner) for c in sc.cases if owner in c.path and c.tag is not None}
    lineno = lambda pos: clean.count("\n", 0, pos) + 1  # noqa: E731
    prefix = f"core.{cls}.{fn}"
    rows: list[Row] = []
    # EndFiber is handled by an `if` before the switch
    if owner == "IO":
        m = re.search(r"if\s*\(\s*_cur0\s+eq\s+IO\.EndFiber\s*\)", clean[span[0] : span[1]])
        if m:
            rows.append(Row(f"{prefix}.EndFiber", area, "runloop-branch", rel, lineno(span[0] + m.start()), "todo", ""))
    cases = match_cases(clean, span[0], span[1], "cur0")
    if not cases:
        raise SystemExit(f"{rel}: no tag switch in {fn}")
    for _, label, pos, nxt in cases:
        name = tags.get(int(label)) if label != "_" else "default"
        if name is None:
            raise SystemExit(f"{rel}:{lineno(pos)}: unknown tag {label}")
        rows.append(Row(f"{prefix}.{name}", area, "runloop-branch", rel, lineno(pos), "todo", ""))
        for scrut in ("ioe", "ioa"):
            for _, sl, spos, _ in match_cases(clean, pos, nxt, scrut):
                sname = tags.get(int(sl)) if sl != "_" else "default"
                rows.append(
                    Row(f"{prefix}.{name}.fast.{sname}", area, "runloop-branch", rel, lineno(spos), "todo", "")
                )
    return rows


def dedupe(rows: list[Row]) -> None:
    seen: Counter[str] = Counter()
    for r in rows:
        seen[r.id] += 1
        if seen[r.id] > 1:
            r.id = f"{r.id}#{seen[r.id]}"


def collect(ce: Path) -> list[Row]:
    files: list[str] = []
    for module in ("kernel", "core", "std", "laws"):
        for p in sorted((ce / module).glob("*/src/main/scala/cats/effect/**/*.scala")):
            rel = p.relative_to(ce).as_posix()
            if module == "laws" and not (rel.startswith("laws/shared/") and p.name.endswith("Laws.scala")):
                continue
            files.append(rel)
    rows: list[Row] = []
    for rel in sorted(files):
        text = (ce / rel).read_text(encoding="utf-8")
        area, status, reason = file_rule(rel)
        sc = scan(text)
        rows.extend(member_rows(rel, sc, area, status, reason))
        if rel == "core/shared/src/main/scala/cats/effect/IOFiber.scala":
            io_text = (ce / "core/shared/src/main/scala/cats/effect/IO.scala").read_text(encoding="utf-8")
            rows.extend(runloop_rows(rel, text, scan(io_text), area, "IO", "runLoop", "IOFiber"))
        if rel == "core/shared/src/main/scala/cats/effect/SyncIO.scala":
            fn = sync_interpreter_name(text)
            rows.extend(runloop_rows(rel, text, sc, area, "SyncIO", fn, "SyncIO"))
    dedupe(rows)
    return rows


def sync_interpreter_name(text: str) -> str:
    clean = strip_comments_and_strings(text)
    m = re.search(r"\(\s*cur0\.tag\s*:\s*@switch\s*\)\s*match", clean)
    if not m:
        raise SystemExit("SyncIO: tag switch not found")
    defs = list(re.finditer(r"\bdef\s+([A-Za-z_]\w*)", clean[: m.start()]))
    return defs[-1].group(1)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ce", default=str(Path.home() / "Projects" / "cats-effect"))
    ap.add_argument("--out", default=str(Path(__file__).resolve().parent.parent / "inventory" / "inventory.csv"))
    ap.add_argument("--allow-other-commit", action="store_true")
    args = ap.parse_args()
    ce = Path(args.ce).expanduser()
    try:
        head = subprocess.run(
            ["git", "-C", str(ce), "rev-parse", "HEAD"], capture_output=True, text=True, check=True
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as e:
        print(f"error: cannot read git HEAD of {ce}: {e}", file=sys.stderr)
        return 1
    if head != PINNED_COMMIT and not args.allow_other_commit:
        print(f"error: {ce} is at {head}, expected v3.7.1 ({PINNED_COMMIT})", file=sys.stderr)
        return 1

    rows = collect(ce)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(COLUMNS)
        for r in rows:
            w.writerow([r.id, r.area, r.kind, r.file, r.line, r.status, r.reason, r.registry])

    print(f"wrote {len(rows)} rows to {out}")
    by = Counter((r.area, r.kind, r.status) for r in rows)
    print(f"{'area':8} {'kind':15} {'status':9} count")
    for (a, k, s), c in sorted(by.items()):
        print(f"{a:8} {k:15} {s:9} {c}")
    reasons = Counter(r.reason.split(":", 1)[0] for r in rows if r.status == "excluded")
    print("excluded by reason prefix: " + ", ".join(f"{k}={v}" for k, v in sorted(reasons.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
