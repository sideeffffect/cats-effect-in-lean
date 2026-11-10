"""Fixed cases: two or more fibers wait on one Deferred when it completes.

The generator has no template for this yet. These cases test the order in which `complete`
resumes the waiters (`CallbackStack.apply`: newest first), a waiter that is canceled before
`complete` (its handle is cleared), and the root as one of the waiters.
Each child maps the value with a different user function, so the trace shows the resume order.

Usage: python3 difftest/cases/gen_deferred.py > difftest/cases/deferred.jsonl
"""
import json


def N(n): return {"t": "nat", "v": n}
def V(x): return {"t": "var", "x": x}
def op(o, **k): d = {"op": o}; d.update(k); return d
def seq(*ps): return op("seq", ps=list(ps))
def delay(fn, arg): return op("delay", fn=fn, arg=arg)
def bind(x, e, k): return op("bind", x=x, e=e, k=k)
def get(d): return op("deferredGet", d=V(d))
def waiter(d, fn): return op("start", e=op("map", e=get(d), fn=fn))
def join(f): return op("join", f=V(f))


cases = []


def case(id, prog, mode="replay", **k):
    c = {"v": 0, "id": id, "mode": mode}
    c.update(k)
    c["prog"] = prog
    cases.append(c)


def two_waiters(body):
    return bind("d", op("deferredNew"), bind("a", waiter("d", 2), bind("b", waiter("d", 4), body)))


complete7 = op("deferredComplete", d=V("d"), v=N(7))

# a waits first, then b; `complete` resumes b first (newest first)
case("deferred-two-waiters-fifo", two_waiters(seq(op("cede"), complete7, join("a"), join("b"))))
# b waits first (choice 1 runs f2 before f1); `complete` resumes a first
case("deferred-two-waiters-chosen", two_waiters(seq(op("cede"), complete7, join("a"), join("b"))),
     choices=[0, 1, 0])
# three waiters
case("deferred-three-waiters",
     bind("d", op("deferredNew"),
          bind("a", waiter("d", 2),
               bind("b", waiter("d", 4),
                    bind("c", waiter("d", 0),
                         seq(op("cede"), complete7, join("a"), join("b"), join("c")))))))
# a is canceled while it waits: its finalizer clears its handle; `complete` resumes only b
case("deferred-waiter-canceled",
     two_waiters(seq(op("cede"), op("cancel", f=V("a")), complete7, join("a"), join("b"))))
# the same with an external cancel of a (handle 1) between the waits and `complete`
case("deferred-waiter-external-cancel",
     two_waiters(seq(op("cede"), complete7, join("a"), join("b"))),
     choices=[0, 0, 0, {"cancel": 1}])
# the root waits too: the root waits first, then a; a child completes
case("deferred-root-and-child-wait",
     bind("d", op("deferredNew"),
          bind("a", waiter("d", 2),
               bind("c", op("start", e=seq(op("cede"), op("deferredComplete", d=V("d"), v=N(3)))),
                    bind("y", get("d"), seq(join("a"), delay(0, V("y"))))))))
# two completes race with two waiters: the second complete returns false
case("deferred-two-waiters-two-completes",
     two_waiters(seq(op("cede"),
                     op("start", e=op("deferredComplete", d=V("d"), v=N(5))),
                     complete7, join("a"), join("b"))))
for c in cases:
    print(json.dumps(c, separators=(",", ":")))
