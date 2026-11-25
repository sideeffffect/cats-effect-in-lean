"""Fixed cases for the format v2 ops of track V (Phase 7): `supUse`, `supervise`
(`std.Supervisor` at v3.7.1, both state kinds, `await = true/false`, the restart path).

Shapes: a child that finishes before the close; a child that never ends (`await = false`:
canceled by the finalizer; `await = true`: the run is `blocked`); several children (the cancel
order of `parUnorderedTraverse`); a child that supervises a grandchild; `supervise` after the
close (`IllegalStateException`, the child never runs); the use body raises or is canceled
(`await = true` then cancels); join and cancel of a supervised fiber; the restart path
(`rs = true`: a child that errors is restarted until the close; cancel of the wrapper);
external cancels; small runtime thresholds.

Usage: python3 difftest/cases/gen_supervisor.py   (writes supervisor.jsonl; then
difftest/run.sh difftest/cases/supervisor.jsonl > difftest/cases/supervisor.expected.jsonl)
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
def emit(n): return delay(1, N(n))
def bind(x, e, k): return op("bind", x=x, e=e, k=k)
def pure(v): return op("pure", v=v)
def start(e): return op("start", e=e)
def join(f): return op("join", f=V(f))
def cancel(f): return op("cancel", f=V(f))
def sup_use(x, k, aw=False, rs=False, cv=False): return op("supUse", aw=aw, rs=rs, cv=cv, x=x, k=k)
def supervise(e, s="s"): return op("supervise", s=V(s), e=e)
def attempt(e): return op("attempt", e=e)
def raise_(c): return op("raise", code=c)
def on_cancel(e, fin, tag): return op("onCancel", e=e, fin=fin, tag=tag)


CEDE = op("cede")
NEVER = op("never")
DONE = pure(UNIT)
RT = [{"cancelationCheckThreshold": 1, "autoYieldThreshold": 2},
      {"cancelationCheckThreshold": 2, "autoYieldThreshold": 4}]

cases = []


def case(id, prog, **k):
    c = {"v": 2, "id": id, "mode": "replay"}
    if "-rs1" in id:
        c["maxSteps"] = 300  # `always` restarts a finished child forever: a join never returns
    c.update(k)
    c["prog"] = prog
    cases.append(c)


KINDS = [(False, False), (False, True), (True, False), (True, True)]  # (rs, cv)

for rs, cv in KINDS:
    tag = f"rs{int(rs)}cv{int(cv)}"
    for aw in (False, True):
        a = f"aw{int(aw)}"
        # one child that finishes before the close
        prog = sup_use("s", bind("f", supervise(seq(emit(100), pure(N(7)))), seq(CEDE, CEDE, join("f"))),
                       aw=aw, rs=rs, cv=cv)
        case(f"sup-one-{a}-{tag}", prog)
        case(f"sup-one-{a}-{tag}-picks", prog, choices=[0, 1, 0, 1, 1, 0])
        # a child that never ends (await = true: blocked)
        prog = sup_use("s", seq(supervise(on_cancel(seq(emit(100), NEVER), emit(101), 1)), CEDE, emit(102), DONE),
                       aw=aw, rs=rs, cv=cv)
        case(f"sup-never-{a}-{tag}", prog)
        for j, rt in enumerate(RT):
            case(f"sup-never-{a}-{tag}-rt{j}", prog, runtime=rt)
        # several children; close while they run
        kids = [on_cancel(seq(emit(100 + i), CEDE, CEDE, emit(110 + i)), emit(120 + i), 10 + i) for i in range(3)]
        prog = sup_use("s", seq(*[supervise(k) for k in kids], emit(130), DONE), aw=aw, rs=rs, cv=cv)
        case(f"sup-three-{a}-{tag}", prog)
        case(f"sup-three-{a}-{tag}-picks", prog, choices=[0, 2, 1, 3, 1, 0, 2, 2, 1, 4, 0, 3])
        # a child supervises a grandchild
        prog = sup_use("s", seq(supervise(seq(emit(100), supervise(seq(emit(101), CEDE, emit(102))), emit(103))),
                                CEDE, CEDE, CEDE, emit(104), DONE), aw=aw, rs=rs, cv=cv)
        case(f"sup-nested-{a}-{tag}", prog)
        case(f"sup-nested-{a}-{tag}-picks", prog, choices=[0, 1, 1, 0, 2, 1, 0, 1])
        # supervise after the close: the supervisor escapes the use body
        prog = bind("t", sup_use("s", pure(V("s")), aw=aw, rs=rs, cv=cv),
                    attempt(supervise(emit(100), s="t")))
        case(f"sup-closed-{a}-{tag}", prog)
        # the use body raises / cancels itself while a child runs
        prog = sup_use("s", seq(supervise(seq(emit(100), CEDE, emit(101))), raise_(5)), aw=aw, rs=rs, cv=cv)
        case(f"sup-body-raise-{a}-{tag}", prog)
        prog = sup_use("s", seq(supervise(seq(emit(100), CEDE, emit(101))), op("canceled")), aw=aw, rs=rs, cv=cv)
        case(f"sup-body-cancel-{a}-{tag}", prog)
        # join and cancel of supervised fibers
        prog = sup_use("s", bind("f", supervise(seq(emit(100), CEDE, raise_(3))),
                                 bind("g", supervise(on_cancel(seq(emit(101), NEVER), emit(102), 2)),
                                      seq(CEDE, cancel("g"), join("g"), join("f")))), aw=aw, rs=rs, cv=cv)
        case(f"sup-join-cancel-{a}-{tag}", prog)
        case(f"sup-join-cancel-{a}-{tag}-picks", prog, choices=[0, 1, 2, 0, 1, 1, 2, 0, 0, 1])
        # a child that errors (restart path: restarted until the close)
        prog = sup_use("s", seq(supervise(seq(emit(100), CEDE, raise_(4))), CEDE, CEDE, CEDE, CEDE, emit(105), DONE),
                       aw=aw, rs=rs, cv=cv)
        case(f"sup-err-{a}-{tag}", prog)
        # external cancels: the child (handle 1), the root
        prog = sup_use("s", bind("f", supervise(on_cancel(seq(emit(100), CEDE, CEDE, emit(101)), emit(102), 3)),
                                 seq(CEDE, CEDE, CEDE, join("f"))), aw=aw, rs=rs, cv=cv)
        case(f"sup-ext-cancel-1-{a}-{tag}", prog, choices=[0, 0, {"cancel": 1}, 0, 0])
        case(f"sup-ext-cancel-root-{a}-{tag}", prog, choices=[0, 0, {"cancel": 0}, 0])

with open(HERE / "supervisor.jsonl", "w") as f:
    for c in cases:
        f.write(json.dumps(c, separators=(",", ":")) + "\n")
print(len(cases), "cases")
