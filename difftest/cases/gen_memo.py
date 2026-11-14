"""Fixed cases for the format v2 ops of track M: `memoize`, `memoGet` (Phase 6, decision 51).

`fa` succeeds, fails, cancels itself, or waits (`cede`, `sleep`); one or two `get` fibers; the
parent cancels one `get` (decision 50), or all `get`s and then runs `get` again (the Scaladoc
"evaluated again"). Runtime thresholds (cancel check, auto-yield) put fiber switches inside
`get`. `m-ce0030-*`: the CE-0030 program (`IO.canceled.memoize`, two `get` fibers) with small
thresholds; some of these are `blocked` (a hung `get`) in Scala and in Lean.
Also prints of a memo handle and of a `Deferred` handle after a `memoize` (handle numbering).

Usage: python3 difftest/cases/gen_memo.py   (writes memoize.jsonl)
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
def memoize(e): return op("memoize", e=e)
def get(m="m"): return op("memoGet", m=V(m))


CEDE = op("cede")
CANCELED = op("canceled")
RAISE = op("raise", code=7)

cases = []


def case(id, prog, **k):
    c = {"v": 2, "id": id, "mode": "replay"}
    c.update(k)
    c["prog"] = prog
    cases.append(c)


FAS = {
    "ok": seq(emit(10), pure(N(5))),
    "err": seq(emit(10), RAISE),
    "self": seq(emit(10), CANCELED, pure(N(5))),
    "wait": seq(emit(10), CEDE, CEDE, pure(N(5))),
    "sleep": seq(emit(10), op("sleep", ms=100), pure(N(5))),
}


def two_gets():
    """`a <- start(get); b <- start(get); pair(join a, join b)`."""
    return bind("a", start(get()), bind("b", start(get()),
                bind("x", join("a"), bind("y", join("b"), seq(delay(1, V("x")), delay(1, V("y")), pure(V("y")))))))


def sequential():
    return bind("x", get(), bind("y", get(), seq(delay(1, V("x")), delay(1, V("y")), pure(V("y")))))


def cancel_one():
    """`a <- start(get); b <- start(get); cede; cancel a; join b`."""
    return bind("a", start(get()), bind("b", start(get()), seq(CEDE, cancel("a"), join("b"))))


def cancel_all_rerun():
    """`a <- start(get); cede; cancel a; get` (the Scaladoc: evaluated again)."""
    return bind("a", start(get()), seq(CEDE, cancel("a"), get()))


RUNTIMES = [None, {"cancelationCheckThreshold": 1, "autoYieldThreshold": 2},
            {"cancelationCheckThreshold": 1, "autoYieldThreshold": 4}]

for fname, fa in FAS.items():
    for bname, body in [("seq", sequential()), ("two", two_gets()), ("c1", cancel_one()), ("rerun", cancel_all_rerun())]:
        for ri, rt in enumerate(RUNTIMES):
            k = {} if rt is None else {"runtime": rt}
            case(f"m-{fname}-{bname}-r{ri}", bind("m", memoize(fa), body), **k)
            case(f"m-{fname}-{bname}-r{ri}-lifo", bind("m", memoize(fa), body), choices=[1, 1, 1, 1, 1, 1], **k)

# CE-0030: IO.canceled.memoize, two get fibers; small thresholds, several pick lists
for ri, rt in enumerate(RUNTIMES):
    for ci, ch in enumerate([[], [1], [0, 1], [1, 1], [0, 0, 1], [1, 0, 1], [2, 1, 0], [0, 1, 1, 2]]):
        k = {} if rt is None else {"runtime": rt}
        case(f"m-ce0030-r{ri}-c{ci}", bind("m", memoize(CANCELED), two_gets()), choices=ch, **k)

# CE-0030 in replay: schedules where Scala ends `blocked` (found by a random search, 16 of 3,000)
for i, ch in enumerate([[2, 3, 2, 3, 1, 2, 3, 0], [3, 1, 2, 3, 1, 2, 0, 0], [3, 0, 0, 1, 2, 1, 2, 0, 0]]):
    case(f"m-ce0030-blocked-{i}", bind("m", memoize(CANCELED), two_gets()), choices=ch,
         runtime={"cancelationCheckThreshold": 1, "autoYieldThreshold": 4})

# handle numbering: a memo handle and a Deferred made after a memoize
case("m-print-handle", bind("m", memoize(pure(N(1))), pure(V("m"))))
case("m-print-deferred", bind("m", memoize(pure(N(1))),
                              seq(get(), bind("d", op("deferredNew"),
                                              seq(op("deferredComplete", d=V("d"), v=N(3)), pure(V("d")))))))
case("m-two-memos", bind("m", memoize(seq(emit(1), pure(N(1)))),
                         bind("n", memoize(seq(emit(2), pure(N(2)))),
                              seq(get("n"), get("m"), get("n"), delay(1, V("m")), pure(V("n"))))))

(HERE / "memoize.jsonl").write_text("".join(json.dumps(c, separators=(",", ":")) + "\n" for c in cases))
print(f"memoize.jsonl: {len(cases)} cases")
