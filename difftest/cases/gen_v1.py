"""Fixed cases for the format v1 ops: `syncStep`, `Resource` (`allocatedCase`), `Queue.unbounded`
and `timeout`. It includes the three calibration witnesses (decision 30):

* CE-0001 case 4 (`syncstep.jsonl`, `ss-ce0001-*`): `IO.uncancelable(_ => IO.canceled *> flag.set(true))`,
  run directly and after `syncStep(Int.MaxValue)`.
* CE-0002 case C (`resource.jsonl`, `res-ce0002-c-*`): `Resource.eval(IO.uncancelable(_ => IO.canceled))
  .allocatedCase` in a fiber, plain and inside `IO.uncancelable`; and the `Resource.make` twin.
* CE-0003 program A, FIFO (`queue.jsonl`, `q-ce0003-a-fifo`): `q.take.timeout(1000 ms).start`,
  `sleep 1`, `offer 42`, `consumer.cancel`, `join`, `tryTake`.

Usage: python3 difftest/cases/gen_v1.py   (writes syncstep.jsonl, resource.jsonl, queue.jsonl)
"""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
UNIT = {"t": "unit"}
MAXINT = 2147483647


def N(n): return {"t": "nat", "v": n}
def B(b): return {"t": "bool", "v": b}
def V(x): return {"t": "var", "x": x}
def op(o, **k): d = {"op": o}; d.update(k); return d
def seq(*ps): return op("seq", ps=list(ps))
def delay(fn, arg=UNIT): return op("delay", fn=fn, arg=arg)
def bind(x, e, k): return op("bind", x=x, e=e, k=k)
def pure(v): return op("pure", v=v)
def unc(p, body): return op("uncancelable", poll=p, body=body)
def start(e): return op("start", e=e)
def join(f): return op("join", f=V(f))
def step(e, limit): return op("syncStep", e=e, limit=limit)
def alloc(r): return op("allocatedCase", res=r)
def rpure(v): return op("rPure", v=v)
def reval(e): return op("rEval", e=e)
def rmake(acq, x, rel): return op("rMake", acq=acq, x=x, rel=rel)
def rflat(r, x, k): return op("rFlatMap", res=r, x=x, k=k)
def qnew(): return op("queueNew")
def offer(q, v): return op("queueOffer", q=V(q), v=v)
def take(q): return op("queueTake", q=V(q))
def trytake(q): return op("queueTryTake", q=V(q))
def timeout(e, ms): return op("timeout", e=e, ms=ms)


files = {}


def case(file, id, prog, **k):
    c = {"v": 1, "id": id, "mode": "replay"}
    c.update(k)
    c["prog"] = prog
    files.setdefault(file, []).append(c)


# ------------------------------------------------------------------ syncStep

S = "syncstep"
# CE-0001 case 4: canceled inside uncancelable is a no-op; the stepped rest has no mask
ce1 = bind("r", op("refNew", v=B(False)), unc("p", seq(op("canceled"), op("refSet", r=V("r"), v=B(True)))))
case(S, "ss-ce0001-direct", ce1)
case(S, "ss-ce0001-stepped", step(ce1, MAXINT))
# CE-0001 case 3 shape: onCancel is dropped by syncStep (external cancel of the root)
oc = op("onCancel", e=seq(delay(1, N(1)), op("never")), fin=delay(1, N(9)), tag=1)
case(S, "ss-oncancel-direct", oc, choices=[0, {"cancel": 0}])
case(S, "ss-oncancel-stepped", step(oc, MAXINT), choices=[0, {"cancel": 0}])
# limits
chain = op("map", e=op("map", e=delay(2, N(1)), fn=2), fn=2)
for lim in (0, 1, 2, 3, 4, MAXINT):
    case(S, f"ss-limit-{lim}", step(chain, lim))
# Right: the whole program is synchronous
case(S, "ss-right", step(seq(delay(1, N(5)), bind("x", delay(2, N(3)), pure(V("x")))), MAXINT))
# an error in the prefix: SyncIO raises, the rest is IO.raiseError
case(S, "ss-raise", step(seq(delay(1, N(1)), op("raise", code=4)), MAXINT))
case(S, "ss-userfn-raise", step(delay(3, N(6)), MAXINT))
case(S, "ss-hew", step(op("handleErrorWith", e=op("raise", code=2), x="c", k=delay(2, V("c"))), MAXINT))
case(S, "ss-hew-left", step(op("handleErrorWith", e=seq(op("cede"), op("raise", code=2)), x="c", k=delay(2, V("c"))), MAXINT))
case(S, "ss-attempt", step(op("attempt", e=op("raise", code=1)), MAXINT))
case(S, "ss-attempt-left", step(op("attempt", e=seq(op("cede"), delay(2, N(0)))), MAXINT))
# stops at the first async boundary (cede, start, async, sleep)
case(S, "ss-cede", step(seq(delay(1, N(1)), op("cede"), delay(1, N(2))), MAXINT))
case(S, "ss-start", step(bind("f", start(delay(2, N(1))), join("f")), MAXINT))
case(S, "ss-async", step(op("async", cbs=[{"when": "later", "ok": N(3)}]), MAXINT))
case(S, "ss-sleep", step(seq(op("sleep", ms=10), delay(1, N(1))), MAXINT))
# refs and deferreds in the prefix
case(S, "ss-ref", step(bind("r", op("refNew", v=N(0)), seq(op("refModify", r=V("r"), fn=5),
                                                             op("refGet", r=V("r")))), MAXINT))
case(S, "ss-deferred", step(bind("d", op("deferredNew"), seq(op("deferredComplete", d=V("d"), v=N(1)),
                                                             op("deferredGet", d=V("d")))), MAXINT))
# poll of the IdPoll is the identity
case(S, "ss-poll", step(unc("p", seq(op("poll", poll="p", e=delay(1, N(1))), op("canceled"), delay(1, N(2)))), MAXINT))
case(S, "ss-poll-cede", step(unc("p", seq(op("poll", poll="p", e=op("cede")), op("canceled"), delay(1, N(2)))), MAXINT))
case(S, "ss-gc", step(op("guaranteeCase", e=delay(2, N(1)), x="o", fin=delay(1, V("o")), tag=2), MAXINT))
# more than SyncStep.MaxSteps = 512 nested flatMaps: the G.defer branch
case(S, "ss-defer-600", step(seq(*[delay(1, N(i)) for i in range(600)]), MAXINT))
case(S, "ss-defer-600-limit", step(seq(*[delay(1, N(i)) for i in range(600)]), 550))

# ------------------------------------------------------------------ Resource

R = "resource"
fa_canceled = unc("p", op("canceled"))
# CE-0002 case C: the outcome of the allocation in a fiber, plain and masked; eval and make
for name, r in (("eval", reval(fa_canceled)), ("make", rmake(fa_canceled, "a", pure(UNIT)))):
    case(R, f"res-ce0002-c-{name}-plain", bind("f", start(alloc(r)), join("f")))
    case(R, f"res-ce0002-c-{name}-masked", bind("f", start(unc("q", alloc(r))), join("f")))
# CE-0002 case B: the continuation after allocatedCase must run
for name, lift in (("eval", reval), ("make", lambda e: rmake(e, "a", pure(UNIT)))):
    r = rflat(rmake(pure(N(42)), "x", pure(UNIT)), "y", lift(fa_canceled))
    body = unc("p", seq(op("poll", poll="p", e=alloc(r)), delay(1, N(7))))
    case(R, f"res-ce0002-b-{name}", bind("f", start(body), join("f")))
case(R, "res-pure", alloc(rpure(N(3))))
case(R, "res-eval", alloc(reval(delay(2, N(1)))))
case(R, "res-make", alloc(rmake(delay(2, N(1)), "x", delay(1, V("x")))))
case(R, "res-flatmap-pure", alloc(rflat(rpure(N(1)), "x", rflat(rpure(V("x")), "y", reval(delay(2, V("y")))))))
# release of the first resource on an error in the rest (rel(ExitCase.Errored(e)))
case(R, "res-release-on-error",
     alloc(rflat(rmake(delay(2, N(1)), "x", delay(1, V("x"))), "y", reval(op("raise", code=3)))))
# release on cancel (rel(ExitCase.Canceled)), external cancel while the rest waits
case(R, "res-release-on-cancel",
     alloc(rflat(rmake(delay(2, N(1)), "x", delay(1, V("x"))), "y", reval(seq(op("cede"), pure(V("y")))))),
     choices=[0, {"cancel": 0}])
case(R, "res-release-raises",
     alloc(rflat(rmake(pure(N(1)), "x", op("raise", code=5)), "y", reval(op("raise", code=3)))))
case(R, "res-two-makes",
     alloc(rflat(rmake(pure(N(1)), "x", delay(1, V("x"))), "y",
                 rflat(rmake(pure(N(2)), "z", delay(1, V("z"))), "w", reval(op("raise", code=0))))))
case(R, "res-acquire-raises", alloc(rmake(op("raise", code=1), "x", delay(1, V("x")))))
case(R, "res-in-fiber-canceled",
     bind("f", start(alloc(rflat(rmake(pure(N(1)), "x", delay(1, V("x"))), "y", reval(op("never"))))),
          seq(op("cede"), op("cancel", f=V("f")), join("f"))))
case(R, "res-bind-captures",
     bind("r", op("refNew", v=N(0)),
          alloc(rflat(rmake(op("refModify", r=V("r"), fn=5), "x", op("refSet", r=V("r"), v=N(9))), "y",
                      reval(seq(op("refGet", r=V("r")), op("raise", code=1)))))))

# ------------------------------------------------------------------ Queue + timeout

Q = "queue"
prog_a = bind("q", qnew(), bind("c", start(timeout(take("q"), 1000)),
                                seq(op("sleep", ms=1), offer("q", N(42)), op("cancel", f=V("c")),
                                    bind("o", join("c"), seq(delay(1, V("o")), trytake("q"))))))
case(Q, "q-ce0003-a-fifo", prog_a)
case(Q, "q-offer-take", bind("q", qnew(), seq(offer("q", N(1)), offer("q", N(2)), take("q"))))
case(Q, "q-trytake-empty", bind("q", qnew(), trytake("q")))
case(Q, "q-trytake", bind("q", qnew(), seq(offer("q", N(5)), trytake("q"))))
case(Q, "q-take-waits", bind("q", qnew(), bind("f", start(take("q")), seq(op("cede"), offer("q", N(3)), join("f")))))
case(Q, "q-two-takers", bind("q", qnew(), bind("f", start(take("q")), bind("g", start(take("q")),
     seq(op("cede"), offer("q", N(1)), offer("q", N(2)), bind("a", join("f"), seq(delay(1, V("a")), join("g"))))))))
case(Q, "q-take-canceled", bind("q", qnew(), bind("f", start(take("q")),
     seq(op("cede"), op("cancel", f=V("f")), offer("q", N(4)), bind("o", join("f"), seq(delay(1, V("o")), trytake("q")))))))
case(Q, "q-take-ext-cancel", bind("q", qnew(), bind("f", start(take("q")),
     seq(op("cede"), offer("q", N(4)), op("cede"), bind("o", join("f"), seq(delay(1, V("o")), trytake("q")))))),
     choices=[0, 0, {"cancel": 1}])
case(Q, "q-timeout-fires", timeout(seq(op("sleep", ms=100), delay(1, N(1))), 10))
case(Q, "q-timeout-ok", timeout(seq(op("sleep", ms=5), delay(2, N(1))), 10))
case(Q, "q-timeout-uncancelable", timeout(unc("p", seq(op("sleep", ms=100), delay(2, N(1)))), 10))
case(Q, "q-timeout-caught", op("handleErrorWith", e=timeout(op("never"), 3), x="c", k=delay(2, V("c"))))
case(Q, "q-timeout-attempt", op("attempt", e=timeout(op("never"), 3)))
case(Q, "q-timeout-error", timeout(op("raise", code=2), 10))
case(Q, "q-timeout-take", bind("q", qnew(), op("attempt", e=timeout(take("q"), 5))))
case(Q, "q-timeout-same-time", timeout(seq(op("sleep", ms=10), delay(2, N(1))), 10))
case(Q, "q-timeout-ext-cancel", timeout(seq(op("cede"), op("sleep", ms=100)), 10), choices=[0, {"cancel": 0}])
case(Q, "q-timeoutTo", op("timeoutTo", e=op("never"), ms=3, fb=delay(2, N(1))))

for name, cs in files.items():
    (HERE / f"{name}.jsonl").write_text("".join(json.dumps(c, separators=(",", ":")) + "\n" for c in cs))
    print(f"{name}.jsonl: {len(cs)} cases")
