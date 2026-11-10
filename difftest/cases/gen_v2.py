"""Fixed cases for the format v2 ops of track G: `guarantee`, `bracket`, `bracketCase`,
`bracketFull` (Phase 6, decision 51).

Each op on success, error, self-cancel and cancel by the parent fiber (decision 50), with the
cancel in acquire, in use and in release. Also the parent-cancel shape of CE-0005
(`br-ce0005-*`): a cancel request during acquire. The difftest language cannot make a `use`
function that throws, so the bug itself is only in `reproducers/CE-0005/Repro.scala`; here both
`IO.bracketFull` and the release outcome are checked for an ordinary `use`.

Usage: python3 difftest/cases/gen_v2.py   (writes bracket.jsonl)
"""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
UNIT = {"t": "unit"}


def N(n): return {"t": "nat", "v": n}
def V(x): return {"t": "var", "x": x}
def op(o, **k): d = {"op": o}; d.update(k); return d
def seq(*ps): return op("seq", ps=list(ps))
def delay(fn, arg=UNIT): return op("delay", fn=fn, arg=arg)
def emit(n): return delay(1, N(n))  # `call` event with arg n (user fn 1 = unit)
def bind(x, e, k): return op("bind", x=x, e=e, k=k)
def pure(v): return op("pure", v=v)
def start(e): return op("start", e=e)
def join(f): return op("join", f=V(f))
def cancel(f): return op("cancel", f=V(f))
def guarantee(e, fin, tag=1): return op("guarantee", e=e, fin=fin, tag=tag)
def bracket(acq, x, use, rel, tag=2): return op("bracket", acq=acq, x=x, use=use, rel=rel, tag=tag)
def bracketCase(acq, x, use, y, rel, tag=3): return op("bracketCase", acq=acq, x=x, use=use, y=y, rel=rel, tag=tag)
def bracketFull(p, acq, x, use, y, rel, tag=4):
    return op("bracketFull", poll=p, acq=acq, x=x, use=use, y=y, rel=rel, tag=tag)


CEDE = op("cede")
CANCELED = op("canceled")
RAISE = op("raise", code=7)

cases = []


def case(id, prog, **k):
    c = {"v": 2, "id": id, "mode": "replay"}
    c.update(k)
    c["prog"] = prog
    cases.append(c)


def parent_cancel(child, cedes):
    """`f <- start(child); cede x cedes; cancel f; join f`."""
    return bind("f", start(child), seq(*([CEDE] * cedes), cancel("f"), join("f")))


# use bodies: success, error, self-cancel, a suspension (so a parent cancel lands in use)
USES = {"ok": lambda x: seq(emit(10), pure(V(x))), "err": lambda x: seq(emit(10), RAISE),
        "self": lambda x: seq(emit(10), CANCELED, pure(V(x))), "wait": lambda x: seq(emit(10), CEDE, CEDE, pure(V(x)))}

# guarantee
for k, e in {"ok": pure(N(1)), "err": RAISE, "self": seq(CANCELED, pure(N(1))), "finerr": pure(N(1))}.items():
    fin = seq(emit(20), RAISE) if k == "finerr" else emit(20)
    case(f"g-{k}", guarantee(seq(emit(10), e), fin))
case("g-err-finerr", guarantee(RAISE, seq(emit(20), op("raise", code=8))))  # reportError
for n in range(4):
    case(f"g-parent-{n}", parent_cancel(guarantee(seq(emit(10), CEDE, CEDE, pure(N(1))), emit(20)), n))

# bracket, bracketCase, bracketFull
ACQ = seq(emit(1), CEDE, pure(N(5)))
for k, use in USES.items():
    case(f"b-{k}", bracket(ACQ, "a", use("a"), seq(emit(20), pure(V("a")))))
    case(f"bc-{k}", bracketCase(ACQ, "a", use("a"), "o", seq(emit(30), pure(V("o")))))
    case(f"bf-{k}", bracketFull("p", ACQ, "a", use("a"), "o", seq(emit(40), pure(V("o")))))
for n in range(5):
    case(f"b-parent-{n}", parent_cancel(bracket(ACQ, "a", USES["wait"]("a"), emit(20)), n))
    case(f"bc-parent-{n}", parent_cancel(bracketCase(ACQ, "a", USES["wait"]("a"), "o", emit(30)), n))
    case(f"bf-parent-{n}", parent_cancel(bracketFull("p", ACQ, "a", USES["wait"]("a"), "o", emit(40)), n))
    # acquire through poll: a cancel there skips use and release
    case(f"bf-poll-{n}", parent_cancel(bracketFull("p", op("poll", poll="p", e=ACQ), "a", USES["ok"]("a"), "o", emit(40)), n))
    # release that suspends: a cancel there must not interrupt it (release is masked)
    case(f"bc-relwait-{n}", parent_cancel(bracketCase(pure(N(5)), "a", USES["ok"]("a"), "o", seq(emit(30), CEDE, CEDE, emit(31))), n))
# CE-0005 shape with an ordinary use: cancel request during acquire (self-cancel in acquire,
# and a parent cancel while acquire suspends)
case("br-ce0005-self", bracketFull("p", seq(CANCELED, pure(N(5))), "a", USES["ok"]("a"), "o", seq(emit(40), pure(V("o")))))
case("br-ce0005-parent", parent_cancel(bracketFull("p", seq(emit(1), CEDE, CEDE, pure(N(5))), "a", USES["ok"]("a"), "o", emit(40)), 1))
# release that raises; nested bracket in use
case("bc-relerr", bracketCase(pure(N(5)), "a", USES["ok"]("a"), "o", seq(emit(30), RAISE)))
case("b-nested", bracket(ACQ, "a", bracket(pure(N(6)), "b", seq(emit(11), CANCELED), emit(21)), emit(20)))

(HERE / "bracket.jsonl").write_text("".join(json.dumps(c, separators=(",", ":")) + "\n" for c in cases))
print(f"bracket.jsonl: {len(cases)} cases")
