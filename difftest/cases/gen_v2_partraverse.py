"""Fixed cases for the format v2 op `parTraverseN` (Phase 6, batch 6.3).

`IO.parTraverseN(n)(xs)(x => f)`: success, error, self-cancel, suspension (cede, sleep), the
limits n = 1 and n >= length, and a parent fiber that cancels the traversal (decision 50).
`partraverse.jsonl` lists have at most 4 elements (`Set1`..`Set4`, a golden file is possible);
`hashcases/partraverse_hash.jsonl` has 5 (a `HashSet`, compared by refinement, no golden file).

Usage: python3 difftest/cases/gen_v2_partraverse.py   (writes partraverse.jsonl)
"""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
UNIT = {"t": "unit"}


def N(n): return {"t": "nat", "v": n}
def V(x): return {"t": "var", "x": x}
def op(o, **k): d = {"op": o}; d.update(k); return d
def seq(*ps): return op("seq", ps=list(ps))
def emit(x): return op("delay", fn=1, arg=x)  # `call` event
def bind(x, e, k): return op("bind", x=x, e=e, k=k)
def pt(n, xs, f): return op("parTraverseN", n=n, xs=xs, x="a", f=f)


CEDE = op("cede")
cases = []


def case(id, prog, **k):
    c = {"v": 2, "id": id, "mode": "replay"}
    c.update(k)
    c["prog"] = prog
    cases.append(c)


F = {
    "pure": op("pure", v=V("a")),
    "emit": seq(emit(V("a")), op("pure", v=V("a"))),
    "cede": seq(emit(V("a")), CEDE, op("map", e=op("pure", v=V("a")), fn=2)),
    "sleep": seq(op("sleep", ms=1), op("pure", v=V("a"))),
    "raise": seq(emit(V("a")), op("raise", code=7)),
    "canceled": seq(emit(V("a")), op("canceled"), op("pure", v=V("a"))),
}
XS = [[], [N(1)], [N(1), N(2)], [N(1), N(2), N(3)], [N(1), N(2), N(3), N(4)]]
for fk in ("pure", "emit", "cede", "sleep"):
    for n in (1, 2, 4):
        for i, xs in enumerate(XS):
            case(f"pt-{fk}-n{n}-l{i}", pt(n, xs, F[fk]))
for fk in ("raise", "canceled"):
    for n in (1, 2, 3):
        case(f"pt-{fk}-n{n}", pt(n, XS[3], F[fk]))
# every element raises its own code (`map(pure a, raise)`): which error wins
for n in (1, 2, 4):
    case(f"pt-err-codes-n{n}", pt(n, XS[4], op("seq", ps=[CEDE, op("map", e=op("pure", v=V("a")), fn=3)])))
# a parent cancels the traversal
for c in range(4):
    case(f"pt-parent-{c}", bind("f", op("start", e=pt(2, XS[3], F["cede"])),
                                seq(*([CEDE] * c), op("cancel", f=V("f")), op("join", f=V("f")))))
# with external cancel choices on the root
case("pt-ext-cancel", pt(1, XS[3], F["cede"]), choices=[0, 0, {"cancel": 0}, 0])

(HERE / "partraverse.jsonl").write_text("".join(json.dumps(c, separators=(",", ":")) + "\n" for c in cases))
print(f"partraverse.jsonl: {len(cases)} cases")

# Review 8: five inputs, so the supervision set becomes a `HashSet` (identity-hash order). These
# cases have no golden file (the order can change between JVM runs): `drive.py check` compares
# them by refinement (`cediff` lists the result of every order of the children, `alternatives`).
cases = []
X5 = [N(1), N(2), N(3), N(4), N(5)]
for fk in ("pure", "emit", "cede", "sleep", "raise", "canceled"):
    for n in (1, 2, 5):
        case(f"pth-{fk}-n{n}", pt(n, X5, F[fk]))
for n in (1, 3, 5):
    case(f"pth-err-codes-n{n}", pt(n, X5, op("seq", ps=[CEDE, op("map", e=op("pure", v=V("a")), fn=3)])))
for c in range(4):
    case(f"pth-parent-{c}", bind("f", op("start", e=pt(5, X5, F["cede"])),
                                 seq(*([CEDE] * c), op("cancel", f=V("f")), op("join", f=V("f")))))
case("pth-ext-cancel", pt(5, X5, F["cede"]), choices=[0, 0, {"cancel": 0}, 0])
# every element emits, sleeps (or cedes), then raises its own code: the first error cancels the
# others through `cancelAll` over the `HashSet` (its order shows in the schedule)
for n in (2, 5):
    case(f"pth-sleep-err-n{n}", pt(n, X5, seq(emit(V("a")), op("sleep", ms=1), op("map", e=op("pure", v=V("a")), fn=3))))
    case(f"pth-cede2-err-n{n}", pt(n, X5, seq(emit(V("a")), CEDE, CEDE, op("map", e=op("pure", v=V("a")), fn=3))))
    case(f"pth-raise-parent-n{n}", bind("f", op("start", e=pt(n, X5, F["sleep"])),
                                         seq(CEDE, CEDE, op("cancel", f=V("f")), op("join", f=V("f")))))
# Regression (track S, 2026-11-15): generated case g61-9094 (seed 61, tpl_sem=20, tpl_mutex=0).
# Its parTraverseN children start fibers of their own, so their fiber ids are not consecutive;
# the first `rankOrder` (rank by `t % k`) missed the Scala order. Frozen here.
G61_9094 = json.loads('{"v":2,"id":"g61-9094","mode":"replay","runtime":{"cancelationCheckThreshold":1,"autoYieldThreshold":3},"prog":{"op":"seq","ps":[{"op":"seq","ps":[{"op":"bind","x":"x1","e":{"op":"start","e":{"op":"raceOutcome","a":{"op":"delay","fn":9,"arg":{"t":"pair","a":{"t":"unit"},"b":{"t":"left","v":{"t":"nat","v":7}}}},"b":{"op":"pure","v":{"t":"nat","v":1}}}},"k":{"op":"seq","ps":[{"op":"sleep","ms":1},{"op":"cancel","f":{"t":"var","x":"x1"}},{"op":"join","f":{"t":"var","x":"x1"}},{"op":"onCancel","e":{"op":"delay","fn":2,"arg":{"t":"nat","v":2}},"fin":{"op":"delay","fn":0,"arg":{"t":"nat","v":1}},"tag":1}]}},{"op":"seq","ps":[{"op":"parTraverseN","n":5,"xs":[{"t":"nat","v":7},{"t":"nat","v":3},{"t":"nat","v":0},{"t":"nat","v":1},{"t":"nat","v":7}],"x":"x10001","f":{"op":"bind","x":"m10002","e":{"op":"memoize","e":{"op":"seq","ps":[{"op":"delay","fn":1,"arg":{"t":"nat","v":9000001}},{"op":"canceled"},{"op":"raise","code":1}]}},"k":{"op":"bind","x":"x10003","e":{"op":"start","e":{"op":"memoGet","m":{"t":"var","x":"m10002"}}},"k":{"op":"seq","ps":[{"op":"cancel","f":{"t":"var","x":"x10003"}},{"op":"bind","x":"x10007","e":{"op":"memoGet","m":{"t":"var","x":"m10002"}},"k":{"op":"seq","ps":[{"op":"delay","fn":1,"arg":{"t":"var","x":"x10007"}},{"op":"uncancelable","poll":"p10006","body":{"op":"async","cbs":[{"when":"later","ok":{"t":"nat","v":1}}]}}]}}]}}}},{"op":"cede"}]}]},{"op":"bind","x":"s30001","e":{"op":"semNew","n":0},"k":{"op":"bind","x":"x30002","e":{"op":"start","e":{"op":"seq","ps":[{"op":"semAcquireN","s":{"t":"var","x":"s30001"},"n":1},{"op":"delay","fn":2,"arg":{"t":"nat","v":1}},{"op":"cede"},{"op":"semReleaseN","s":{"t":"var","x":"s30001"},"n":1}]}},"k":{"op":"bind","x":"x30003","e":{"op":"start","e":{"op":"map","e":{"op":"seq","ps":[{"op":"cede"},{"op":"semAvailable","s":{"t":"var","x":"s30001"}}]},"fn":1}},"k":{"op":"bind","x":"x30004","e":{"op":"start","e":{"op":"map","e":{"op":"seq","ps":[{"op":"semTryAcquireN","s":{"t":"var","x":"s30001"},"n":1},{"op":"semCount","s":{"t":"var","x":"s30001"}}]},"fn":1}},"k":{"op":"seq","ps":[{"op":"semReleaseN","s":{"t":"var","x":"s30001"},"n":1},{"op":"cede"},{"op":"cancel","f":{"t":"var","x":"x30003"}},{"op":"cancel","f":{"t":"var","x":"x30004"}},{"op":"map","e":{"op":"join","f":{"t":"var","x":"x30002"}},"fn":1},{"op":"map","e":{"op":"semAvailable","s":{"t":"var","x":"s30001"}},"fn":1},{"op":"map","e":{"op":"semCount","s":{"t":"var","x":"s30001"}},"fn":1}]}}}}}]}}')
G61_9094["id"] = "pth-regress-g61-9094"
cases.append(G61_9094)
HASH = HERE.parent / "hashcases"
HASH.mkdir(exist_ok=True)
(HASH / "partraverse_hash.jsonl").write_text("".join(json.dumps(c, separators=(",", ":")) + "\n" for c in cases))
print(f"hashcases/partraverse_hash.jsonl: {len(cases)} cases")
