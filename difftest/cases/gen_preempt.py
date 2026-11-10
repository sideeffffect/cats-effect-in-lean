"""Cases with small IORuntimeConfig thresholds (case field `runtime`) and `timeoutTo` with a
user fallback. An auto-yield after every few run-loop iterations has the effect of a `preempt`
choice of CatsEffectInLean/Model/SchedP.lean (Phase 5 gate caveat 3).

Usage: python3 difftest/cases/gen_preempt.py > difftest/cases/preempt.jsonl
"""
import json


def N(n): return {"t": "nat", "v": n}
def V(x): return {"t": "var", "x": x}
def op(o, **k): d = {"op": o}; d.update(k); return d
def seq(*ps): return op("seq", ps=list(ps))
def delay(fn, arg): return op("delay", fn=fn, arg=arg)
def bind(x, e, k): return op("bind", x=x, e=e, k=k)
def rt(c, a): return {"cancelationCheckThreshold": c, "autoYieldThreshold": a}


cases = []


def case(id, prog, **k):
    c = {"v": 1, "id": id, "mode": "replay"}
    c.update(k)
    c["prog"] = prog
    cases.append(c)


# Two fibers with three delays each and no cede. Default config: each child runs to its end
# in one task. With an auto-yield every 2 iterations, each child runs in many tasks (the trace
# order is the same as with the default config, in Scala and in Lean; not analysed further).
def two_children():
    a = seq(delay(0, N(1)), delay(0, N(2)), delay(0, N(3)))
    b = seq(delay(0, N(4)), delay(0, N(5)), delay(0, N(6)))
    return bind("a", op("start", e=a), bind("b", op("start", e=b),
                                            seq(op("join", f=V("a")), op("join", f=V("b")))))


case("pre-two-default", two_children())
case("pre-two-ay2", two_children(), runtime=rt(1, 2))
case("pre-two-ay4", two_children(), runtime=rt(2, 4))
case("pre-two-ay2-picks", two_children(), runtime=rt(1, 2), choices=[0, 1, 1, 0, 2, 1, 0])
case("pre-two-ay2-last", two_children(), runtime=rt(1, 2), choices=[2] * 20)

# A cancel that lands inside a run of delays: with an auto-yield the canceler runs between
# two iterations of the child, so the child stops before its last delay.
def cancel_mid():
    child = op("onCancel", e=seq(delay(0, N(1)), delay(0, N(2)), delay(0, N(3)), delay(0, N(4))),
               fin=delay(1, N(9)), tag=1)
    return bind("f", op("start", e=child), seq(op("cede"), op("cancel", f=V("f")), op("join", f=V("f"))))


case("pre-cancel-mid-default", cancel_mid())
case("pre-cancel-mid-ay2", cancel_mid(), runtime=rt(1, 2))
case("pre-cancel-mid-ay3", cancel_mid(), runtime=rt(1, 3))
case("pre-cancel-mid-ext", cancel_mid(), runtime=rt(1, 2), choices=[0, 1, {"cancel": 1}])

# A masked region: an auto-yield inside `uncancelable` does not unmask it.
def masked():
    child = op("uncancelable", poll="p", body=seq(delay(0, N(1)), delay(0, N(2)), delay(0, N(3))))
    return bind("f", op("start", e=child), seq(op("cede"), op("cancel", f=V("f")), op("join", f=V("f"))))


case("pre-masked-ay2", masked(), runtime=rt(1, 2))

# timeoutTo with a user fallback: the source waits, the timeout fires, the fallback runs.
case("tto-fires", op("timeoutTo", e=seq(op("sleep", ms=100), delay(0, N(1))), ms=10, fb=delay(0, N(7))))
# The source wins: the fallback does not run.
case("tto-source-wins", op("timeoutTo", e=delay(0, N(1)), ms=10, fb=delay(0, N(7))))
# The fallback raises.
case("tto-fallback-raises", op("timeoutTo", e=op("never"), ms=1, fb=op("raise", code=5)))
# Small thresholds around a timeoutTo.
case("tto-fires-ay2", op("timeoutTo", e=seq(op("sleep", ms=100), delay(0, N(1))), ms=10, fb=delay(0, N(7))),
     runtime=rt(1, 2))

for c in cases:
    print(json.dumps(c, separators=(",", ":")))
