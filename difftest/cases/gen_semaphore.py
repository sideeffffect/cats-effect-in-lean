"""Fixed cases for the format v2 ops of Phase 7 track S: `std.Semaphore` and `std.Mutex`.

Ops: `semNew`, `semAcquireN`, `semReleaseN`, `semTryAcquireN`, `semAvailable`, `semCount`,
`semPermit`, `mutexNew`, `mutexLock` (wiki/methodology/difftest-program-format.md). The cases cover
the paths of `Semaphore.scala` at v3.7.1 (immediate acquire, enqueue, partial and full `fulfil`,
`wake` of a canceled request, `sweep`, `reclaim` of the head and of a non-head request, a cancel
after the gate was completed, `tryAcquireN`, `count` with waiters and with a canceled waiter: the
CE-0060 shape) and of `LockQueue.scala` (free lock, a waiter, a canceled waiter with and without a
successor, release while nobody waits).

Usage: python3 difftest/cases/gen_semaphore.py   (writes semaphore.jsonl)
"""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
UNIT = {"t": "unit"}


def N(n): return {"t": "nat", "v": n}
def V(x): return {"t": "var", "x": x}
def op(o, **k): d = {"op": o}; d.update(k); return d
def seq(*ps): return op("seq", ps=list(ps))
def bind(x, e, k): return op("bind", x=x, e=e, k=k)
def mark(k): return op("delay", fn=2, arg=N(k))
def start(e): return op("start", e=e)
def acq(s, n): return op("semAcquireN", s=V(s), n=n)
def rel(s, n): return op("semReleaseN", s=V(s), n=n)
def cnt(s): return op("semCount", s=V(s))
def avail(s): return op("semAvailable", s=V(s))


def case(cid, prog, choices=None, runtime=None):
    c = {"v": 2, "id": cid, "mode": "replay"}
    if choices:
        c["choices"] = choices
    if runtime:
        c["runtime"] = runtime
    c["prog"] = prog
    return c


CASES = [
    case("sem-new-available", bind("s", op("semNew", n=2), avail("s"))),
    case("sem-handle", op("semNew", n=0)),
    case("sem-acquire-count", bind("s", op("semNew", n=2), seq(acq("s", 2), cnt("s")))),
    case("sem-zero-ops", bind("s", op("semNew", n=0), seq(acq("s", 0), rel("s", 0),
                                                           op("semTryAcquireN", s=V("s"), n=0)))),
    case("sem-try", bind("s", op("semNew", n=1), seq(op("semTryAcquireN", s=V("s"), n=2),
                                                     op("semTryAcquireN", s=V("s"), n=1)))),
    case("sem-permit", bind("s", op("semNew", n=1), seq(op("semPermit", s=V("s"), e=mark(4)), avail("s")))),
    case("sem-permit-raise", bind("s", op("semNew", n=1),
                                  seq(op("attempt", e=op("semPermit", s=V("s"), e=op("raise", code=3))), avail("s")))),
    case("sem-wait-release", bind("s", op("semNew", n=0), bind("f", start(acq("s", 2)), seq(
        op("cede"), cnt("s"), rel("s", 3), op("join", f=V("f")), avail("s"))))),
    # partial fulfil: a request for 3 gets 1, then 2
    case("sem-partial", bind("s", op("semNew", n=0), bind("f", start(seq(acq("s", 3), mark(1))), seq(
        op("cede"), rel("s", 1), cnt("s"), rel("s", 2), op("join", f=V("f")), avail("s"))))),
    # cancel of a partially filled head: reclaim gives back the sunk permit
    case("sem-cancel-partial-head", bind("s", op("semNew", n=0), bind("f", start(acq("s", 3)), seq(
        op("cede"), rel("s", 2), op("cancel", f=V("f")), avail("s"), cnt("s"))))),
    # CE-0060: two canceled waiters, non-head first; count stays -1
    case("sem-ghost-count", bind("s", op("semNew", n=0), bind("a", start(acq("s", 1)), bind("b", start(acq("s", 1)), seq(
        op("cede"), op("cancel", f=V("b")), op("cancel", f=V("a")), cnt("s")))))),
    # a release reaches the canceled request (wake: complete is false, releaseN(requested))
    case("sem-ghost-wake", bind("s", op("semNew", n=0), bind("a", start(acq("s", 1)), bind("b", start(seq(acq("s", 1), mark(2))), seq(
        op("cede"), op("cancel", f=V("a")), rel("s", 1), op("join", f=V("b")), avail("s"), cnt("s")))))),
    # sweep: the head of waitingNow is canceled after a partial fill
    case("sem-sweep", bind("s", op("semNew", n=0), bind("a", start(acq("s", 1)), bind("b", start(acq("s", 2)), bind("c", start(seq(acq("s", 1), mark(3))), seq(
        op("cede"), op("cancel", f=V("b")), rel("s", 2), op("join", f=V("c")), avail("s"), cnt("s"))))))),
    # FIFO: a later small request waits behind an earlier big one
    case("sem-fifo", bind("s", op("semNew", n=0), bind("a", start(seq(acq("s", 2), mark(1))), bind("b", start(seq(acq("s", 1), mark(2))), seq(
        op("cede"), rel("s", 1), cnt("s"), rel("s", 2), op("join", f=V("a")), op("join", f=V("b")), cnt("s")))))),
    # masked acquire: canceled while it waits, then given the permit
    case("sem-masked", bind("s", op("semNew", n=0), bind("f", start(op("uncancelable", poll="p", body=seq(
        op("poll", poll="p", e=acq("s", 1)), mark(5), rel("s", 1)))), seq(
        op("cede"), rel("s", 1), op("cancel", f=V("f")), avail("s"))))),
    # a cancel that lands after the permit was handed over (small runtime thresholds)
    case("sem-cancel-after-grant", bind("s", op("semNew", n=0), bind("f", start(acq("s", 1)), seq(
        op("cede"), rel("s", 1), op("cancel", f=V("f")), avail("s"), cnt("s")))),
        runtime={"cancelationCheckThreshold": 1, "autoYieldThreshold": 2}),
    case("sem-permit-contend", bind("s", op("semNew", n=1), bind("f", start(op("semPermit", s=V("s"), e=seq(op("cede"), mark(1)))), seq(
        op("semPermit", s=V("s"), e=mark(2)), op("join", f=V("f")), avail("s"))))),
    case("sem-permit-cancel", bind("s", op("semNew", n=1), bind("f", start(op("semPermit", s=V("s"), e=seq(op("cede"), op("cede"), mark(1)))), seq(
        op("cede"), op("cancel", f=V("f")), avail("s"), cnt("s")))), choices=[0, 1, 0, 0, 1]),
    case("mutex-lock", bind("m", op("mutexNew"), seq(op("mutexLock", m=V("m"), e=mark(1)),
                                                     op("mutexLock", m=V("m"), e=op("pure", v=V("m")))))),
    case("mutex-contend", bind("m", op("mutexNew"), bind("f", start(op("mutexLock", m=V("m"), e=seq(op("cede"), mark(1)))), seq(
        op("cede"), op("mutexLock", m=V("m"), e=mark(5)), op("join", f=V("f")))))),
    case("mutex-cancel-waiter", bind("m", op("mutexNew"), bind("f", start(op("mutexLock", m=V("m"), e=seq(op("cede"), op("cede"), mark(1)))),
        bind("g", start(op("mutexLock", m=V("m"), e=mark(7))), seq(
            op("cede"), op("cancel", f=V("g")), op("join", f=V("f")), op("mutexLock", m=V("m"), e=mark(9))))))),
    # a canceled waiter with a successor: the successor gets the predecessor's cell
    case("mutex-cancel-middle", bind("m", op("mutexNew"), bind("f", start(op("mutexLock", m=V("m"), e=seq(op("cede"), op("cede"), mark(1)))),
        bind("g", start(op("mutexLock", m=V("m"), e=mark(2))), bind("h", start(op("mutexLock", m=V("m"), e=mark(3))), seq(
            op("cede"), op("cancel", f=V("g")), op("join", f=V("h")), op("join", f=V("f")),
            op("mutexLock", m=V("m"), e=mark(9)))))))),
    case("mutex-cancel-holder", bind("m", op("mutexNew"), bind("f", start(op("mutexLock", m=V("m"), e=op("never"))), seq(
        op("cede"), op("cancel", f=V("f")), op("mutexLock", m=V("m"), e=mark(4)))))),
    case("mutex-raise", bind("m", op("mutexNew"), seq(op("attempt", e=op("mutexLock", m=V("m"), e=op("raise", code=1))),
                                                      op("mutexLock", m=V("m"), e=mark(2))))),
]


def main():
    out = HERE / "semaphore.jsonl"
    out.write_text("".join(json.dumps(c) + "\n" for c in CASES))
    print(f"wrote {len(CASES)} cases to {out}")


if __name__ == "__main__":
    main()
