"""Cases for the multi-fiber scheduler hand examples (CatsEffectInLean/Model/SchedExamples.lean).

Usage: python3 difftest/cases/gen_sched.py > difftest/cases/sched.jsonl
"""
import json


def N(n): return {"t": "nat", "v": n}
def V(x): return {"t": "var", "x": x}
def op(o, **k): d = {"op": o}; d.update(k); return d
def seq(*ps): return op("seq", ps=list(ps))
def delay(fn, arg): return op("delay", fn=fn, arg=arg)
def bind(x, e, k): return op("bind", x=x, e=e, k=k)


cases = []


def case(id, prog, mode="replay", **k):
    c = {"v": 0, "id": id, "mode": mode}
    c.update(k)
    c["prog"] = prog
    cases.append(c)


case("start-join", bind("f", op("start", e=delay(0, N(5))), op("join", f=V("f"))))
case("cancel-child-oncancel",
     bind("f", op("start", e=op("onCancel", e=op("never"), fin=delay(1, N(9)), tag=1)),
          seq(op("cede"), op("cancel", f=V("f")), op("join", f=V("f")))))
case("cancel-child-masked",
     bind("f", op("start", e=seq(op("uncancelable", poll="p", body=seq(op("cede"), delay(0, N(1)))),
                                 delay(0, N(2)))),
          seq(op("cede"), op("cancel", f=V("f")), op("join", f=V("f")))))
case("cancel-child-masked-end",
     bind("f", op("start", e=op("uncancelable", poll="p", body=seq(op("cede"), delay(0, N(1))))),
          seq(op("cede"), op("cancel", f=V("f")), op("join", f=V("f")))))
case("async-later-cancel",
     op("async", cbs=[{"when": "later", "ok": N(1)}], fin=delay(1, N(0)), tag=5),
     choices=[0, {"cancel": 0}])
case("external-cancel-root-before-start", op("pure", v=N(1)), choices=[{"cancel": 0}])
for c in cases:
    print(json.dumps(c, separators=(",", ":")))
