"""Fixed cases for the format v2 ops of track L (Phase 7): `cdlNew`, `cdlRelease`, `cdlAwait`,
`cbNew`, `cbAwait` (`std.CountDownLatch`, `std.CyclicBarrier` at v3.7.1).

CountDownLatch: counts 1-3; waiters before and after the count reaches 0; `release` after
`Done` (a no-op); a canceled waiter while others still wake; a waiter that is never released
(the run is `blocked`); external cancel choices; small runtime thresholds (auto-yield inside
`release`/`await`).
CyclicBarrier: one and two generations; a canceled waiter that leaves the count (the next
fibers do not trip early); the cancel-versus-trip race (`CyclicBarrier.scala:77-82`: the waiter
is canceled while suspended, another fiber trips the barrier before the waiter's cleanup task
runs, so the cleanup sees the new epoch); a masked self-cancel; a blocked run; small thresholds.

Usage: python3 difftest/cases/gen_latch.py   (writes latch.jsonl; then
difftest/run.sh difftest/cases/latch.jsonl > difftest/cases/latch.expected.jsonl)
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
def rel(l="l"): return op("cdlRelease", l=V(l))
def aw(l="l"): return op("cdlAwait", l=V(l))
def baw(b="b"): return op("cbAwait", b=V(b))


CEDE = op("cede")
DONE = pure(UNIT)

cases = []


def case(id, prog, **k):
    c = {"v": 2, "id": id, "mode": "replay"}
    c.update(k)
    c["prog"] = prog
    cases.append(c)


def starts(names, bodies, k):
    """`x1 <- start(b1); ...; k`."""
    for x, b in reversed(list(zip(names, bodies))):
        k = bind(x, start(b), k)
    return k


def joins(*fs):
    return [join(f) for f in fs]


RT = [{"cancelationCheckThreshold": 1, "autoYieldThreshold": 2},
      {"cancelationCheckThreshold": 1, "autoYieldThreshold": 3},
      {"cancelationCheckThreshold": 2, "autoYieldThreshold": 6}]

# ---------------------------------------------------------------- CountDownLatch

for n in (1, 2, 3):
    # waiters first, then n releases by the parent, then one more release (no-op), late await
    prog = bind("l", op("cdlNew", n=n), starts(["a", "b"], [seq(aw(), emit(100)), seq(aw(), emit(101))],
        seq(*([CEDE] + [seq(rel(), emit(200 + i)) for i in range(n)] + [rel(), emit(299), aw(), emit(102)]
              + joins("a", "b") + [DONE]))))
    case(f"cdl-basic-{n}", prog)
    for j, rt in enumerate(RT):
        case(f"cdl-basic-{n}-rt{j}", prog, runtime=rt)
    # releasers in fibers
    prog = bind("l", op("cdlNew", n=n), starts(["a"] + [f"r{i}" for i in range(n + 1)],
        [seq(aw(), emit(100))] + [seq(emit(200 + i), rel()) for i in range(n + 1)],
        seq(*(joins("a", *[f"r{i}" for i in range(n + 1)]) + [DONE]))))
    case(f"cdl-releasers-{n}", prog)
    case(f"cdl-releasers-{n}-picks", prog, choices=[0, 2, 1, 3, 1, 0, 2, 2, 1])
    case(f"cdl-releasers-{n}-rt", prog, runtime=RT[0], choices=[1, 0, 2, 1])

# a canceled waiter; the other waiter still wakes
prog = bind("l", op("cdlNew", n=2), starts(["a", "b"],
    [seq(op("onCancel", e=aw(), fin=emit(900), tag=1), emit(100)), seq(aw(), emit(101))],
    seq(CEDE, cancel("a"), rel(), CEDE, rel(), *joins("a", "b"), DONE)))
case("cdl-cancel-waiter", prog)
case("cdl-cancel-waiter-rt", prog, runtime=RT[1])
# a waiter in uncancelable + poll, canceled
prog = bind("l", op("cdlNew", n=1), starts(["a"],
    [op("uncancelable", poll="p", body=seq(emit(300), op("onCancel", e=op("poll", poll="p", e=aw()), fin=emit(901), tag=2), emit(301)))],
    seq(CEDE, cancel("a"), rel(), join("a"), DONE)))
case("cdl-poll-waiter", prog)
# never released: blocked
prog = bind("l", op("cdlNew", n=2), starts(["a"], [seq(aw(), emit(100))], seq(rel(), join("a"), DONE)))
case("cdl-blocked", prog)
# external cancel choices (the waiter, the root)
prog = bind("l", op("cdlNew", n=1), starts(["a", "b"], [seq(aw(), emit(100)), seq(CEDE, rel(), emit(200))],
    seq(*joins("a", "b"), DONE)))
case("cdl-ext-cancel-1", prog, choices=[0, {"cancel": 1}, 0, 0])
case("cdl-ext-cancel-2", prog, choices=[0, 1, {"cancel": 2}, 0])
case("cdl-ext-cancel-root", prog, choices=[0, 0, {"cancel": 0}])
# release inside uncancelable, self-cancel before it
prog = bind("l", op("cdlNew", n=1), starts(["a", "r"], [seq(aw(), emit(100)),
    op("uncancelable", poll="q", body=seq(op("canceled"), rel(), emit(201)))], seq(*joins("a", "r"), DONE)))
case("cdl-masked-selfcancel", prog)

# ---------------------------------------------------------------- CyclicBarrier

for cap in (1, 2, 3):
    k = 2 * cap
    names = [f"a{i}" for i in range(k)]
    prog = bind("b", op("cbNew", n=cap), starts(names, [seq(baw(), emit(100 + i)) for i in range(k)],
        seq(*(joins(*names) + [DONE]))))
    case(f"cb-two-gen-{cap}", prog)
    case(f"cb-two-gen-{cap}-picks", prog, choices=[0, 2, 1, 3, 0, 2, 1])
    for j, rt in enumerate(RT):
        case(f"cb-two-gen-{cap}-rt{j}", prog, runtime=rt)

# a canceled waiter leaves the count: the next fiber does not trip alone
prog = bind("b", op("cbNew", n=2), starts(["a"], [seq(op("onCancel", e=baw(), fin=emit(900), tag=3), emit(100))],
    seq(CEDE, cancel("a"), starts(["c", "d"], [seq(baw(), emit(101)), seq(CEDE, baw(), emit(102))],
        seq(*joins("a", "c", "d"), DONE)))))
case("cb-cancel-removed", prog)
case("cb-cancel-removed-rt", prog, runtime=RT[2])
# the cancel-versus-trip race (cap 2 and 3): waiters wait, the parent starts a tripper and cancels
for cap in (2, 3):
    ws = [f"w{i}" for i in range(cap - 1)]
    late = [f"z{i}" for i in range(cap)]
    prog = bind("b", op("cbNew", n=cap), starts(ws, [seq(baw(), emit(100 + i)) for i in range(cap - 1)],
        seq(CEDE, starts(["t"], [seq(baw(), emit(150))],
            seq(cancel("w0"), starts(late, [seq(baw(), emit(160 + i)) for i in range(cap)],
                seq(*(joins(*ws, "t", *late) + [DONE]))))))))
    case(f"cb-race-{cap}", prog)
    case(f"cb-race-{cap}-rt", prog, runtime=RT[0])
# masked self-cancel: the cancel is seen at the poll around await
prog = bind("b", op("cbNew", n=2), starts(["a", "c", "d"], [
    op("uncancelable", poll="p", body=seq(op("canceled"), emit(300), op("onCancel", e=op("poll", poll="p", e=baw()), fin=emit(902), tag=4), emit(301))),
    seq(baw(), emit(101)), seq(CEDE, baw(), emit(102))], seq(*joins("a", "c", "d"), DONE)))
case("cb-masked-selfcancel", prog)
# blocked: one waiter alone
prog = bind("b", op("cbNew", n=2), starts(["a"], [seq(baw(), emit(100))], seq(join("a"), DONE)))
case("cb-blocked", prog)
# external cancels
prog = bind("b", op("cbNew", n=2), starts(["a", "c"], [seq(baw(), emit(100)), seq(CEDE, CEDE, baw(), emit(101))],
    seq(*joins("a", "c"), DONE)))
case("cb-ext-cancel-1", prog, choices=[0, 0, {"cancel": 1}, 0, 0])
case("cb-ext-cancel-2", prog, choices=[0, 1, 0, {"cancel": 2}])

with open(HERE / "latch.jsonl", "w") as f:
    for c in cases:
        f.write(json.dumps(c, separators=(",", ":")) + "\n")
print(len(cases), "cases")
