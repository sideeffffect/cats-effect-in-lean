"""Fixed cases for the format v2 ops of track Res: `rUse`, `rAllocated`, `rBoth` (Phase 6,
batch 6.2, decision 51).

`use` and `allocated` on success, error, self-cancel and cancel by the parent fiber
(decision 50), with nested `flatMap` (finalizer order). `both` with ordinary sides, with a
release that raises an error (the shape of CE-0020), and with several schedules (`choices`), so
that the second release can be skipped.

Usage: python3 difftest/cases/gen_res.py   (writes resuse.jsonl)
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
def make(acq, x, rel): return op("rMake", acq=acq, x=x, rel=rel)
def rfm(r, x, k): return op("rFlatMap", res=r, x=x, k=k)
def reval(e): return op("rEval", e=e)
def rpure(v): return op("rPure", v=v)
def use(r, x, k): return op("rUse", res=r, x=x, k=k)
def allocated(r, x, k): return op("rAllocated", res=r, x=x, k=k)
def both(a, b): return op("rBoth", a=a, b=b)


CEDE = op("cede")
CANCELED = op("canceled")
RAISE = op("raise", code=7)


def mk(n, rel_extra=None):
    """`make(emit n; pure n)(_ => emit (100 + n) [; rel_extra])`."""
    rel = emit(100 + n) if rel_extra is None else seq(emit(100 + n), rel_extra)
    return make(seq(emit(n), pure(N(n))), "a", rel)


def parent(e):
    """`e.start.flatMap(f => f.cancel *> f.join)` (decision 50)."""
    return bind("f", start(e), seq(cancel("f"), join("f")))


def cases():
    out = []

    def add(name, prog, choices=None):
        c = {"v": 2, "id": f"res-{name}", "mode": "replay", "prog": prog}
        if choices is not None:
            c["choices"] = choices
        out.append(c)

    two = rfm(mk(1), "x", mk(2))
    three = rfm(mk(1), "x", rfm(mk(2), "y", mk(3)))
    bodies = {
        "ok": emit(50),
        "err": seq(emit(50), RAISE),
        "cancel": seq(emit(50), CANCELED),
        "cede": seq(CEDE, emit(50)),
    }
    for rn, r in [("one", mk(1)), ("two", two), ("three", three), ("pure", rpure(N(9))),
                  ("eval", reval(seq(emit(9), pure(N(9))))), ("evalcancel", rfm(mk(1), "x", reval(CANCELED)))]:
        for bn, b in bodies.items():
            add(f"use-{rn}-{bn}", use(r, "v", b))
            add(f"alloc-{rn}-{bn}", allocated(r, "v", b))
        add(f"use-{rn}-parent", parent(use(r, "v", seq(CEDE, emit(50)))))
        add(f"alloc-{rn}-parent", parent(allocated(r, "v", seq(CEDE, emit(50)))))
    # `both`
    b0 = both(mk(1), mk(2))
    bfail = both(mk(1, RAISE), mk(2))
    bnest = both(two, rfm(mk(3), "z", mk(4)))
    bacqfail = both(make(seq(emit(1), RAISE), "a", emit(101)), mk(2))
    bcancel = both(make(seq(emit(1), CANCELED), "a", emit(101)), mk(2))
    for bn, b in [("plain", b0), ("relfail", bfail), ("nested", bnest), ("acqfail", bacqfail),
                  ("acqcancel", bcancel), ("inner", both(both(mk(1), mk(2)), mk(3)))]:
        add(f"both-{bn}-use", use(b, "v", emit(50)))
        add(f"both-{bn}-useerr", use(b, "v", RAISE))
        add(f"both-{bn}-alloc", allocated(b, "v", emit(50)))
        add(f"both-{bn}-parent", parent(use(b, "v", seq(CEDE, emit(50)))))
        for k in range(0, 12):
            for d in (1, 2):
                add(f"both-{bn}-sched{k}-{d}", use(b, "v", emit(50)), [0] * k + [d])
    return out


def main():
    cs = cases()
    with open(HERE / "resuse.jsonl", "w") as f:
        for c in cs:
            f.write(json.dumps(c, separators=(",", ":")) + "\n")
    print(f"{len(cs)} cases")


if __name__ == "__main__":
    main()
