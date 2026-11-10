"""Fixed cases for `racePair` and `sleep` (hand examples in
CatsEffectInLean/Model/RaceSleepExamples.lean).

Usage: python3 difftest/cases/gen_racesleep.py > difftest/cases/racesleep.jsonl
"""
import json


def N(n): return {"t": "nat", "v": n}
def V(x): return {"t": "var", "x": x}
def op(o, **k): d = {"op": o}; d.update(k); return d
def seq(*ps): return op("seq", ps=list(ps))
def delay(fn, arg): return op("delay", fn=fn, arg=arg)
def bind(x, e, k): return op("bind", x=x, e=e, k=k)
def sleep(ms): return op("sleep", ms=ms)
def race(a, b): return op("racePair", a=a, b=b)


cases = []


def case(id, prog, mode="replay", **k):
    c = {"v": 0, "id": id, "mode": mode}
    c.update(k)
    c["prog"] = prog
    cases.append(c)


def cancel_loser(r):
    """case r of Left(o, f) / Right(f, o): cancel the loser f, then join it."""
    k = seq(op("cancel", f=V("f")), op("join", f=V("f")))
    return op("case", on=V(r), l="l", lk=op("split", on=V("l"), a="o", b="f", k=k),
              r="q", rk=op("split", on=V("q"), a="f", b="o", k=k))


loser = op("onCancel", e=op("never"), fin=delay(1, N(9)), tag=1)

# racePair: A wins; the loser B is not canceled by racePair
case("race-left-wins", race(delay(0, N(1)), seq(op("cede"), delay(0, N(2)))))
# racePair: B wins
case("race-right-wins", race(seq(op("cede"), op("cede"), delay(0, N(1))), delay(0, N(2))))
# A wins; the program cancels the loser, which runs its finalizer
case("race-loser-cancel", bind("r", race(op("pure", v=N(1)), loser), cancel_loser("r")))
# A fails: Left(Errored, fiber)
case("race-left-error", race(op("raise", code=4), op("never")))
# the root is canceled while it waits: racePair cancels A, then B, and joins both
case("race-root-canceled",
     race(op("onCancel", e=op("never"), fin=delay(1, N(8)), tag=2), loser),
     choices=[0, 0, 0, {"cancel": 0}])
# timers: B wakes first; A's timer stays pending (not canceled)
case("race-sleep", race(sleep(10), sleep(5)))
# timers with the same due time wake in creation order; the root sleeps last
case("sleep-order",
     seq(op("start", e=seq(sleep(20), delay(0, N(1)))),
         op("start", e=seq(sleep(10), delay(0, N(2)))),
         op("start", e=seq(sleep(10), delay(0, N(3)))),
         sleep(30)))
# two sleeps in a row: time adds up
case("sleep-twice", seq(sleep(5), sleep(7), delay(0, N(1))))
# sleep(0) is IO.cede (no timer)
case("sleep-zero", seq(sleep(0), delay(0, N(1))))
# external cancel of a sleeping root: the finalizer removes the timer
case("sleep-external-cancel", op("onCancel", e=sleep(100), fin=delay(1, N(9)), tag=3),
     choices=[0, {"cancel": 0}])
# a child sleeps; the root cancels it; the timer is removed, so time does not move
case("sleep-cancel-child",
     bind("f", op("start", e=sleep(50)), seq(op("cede"), op("cancel", f=V("f")), op("join", f=V("f")))))
# twins: a failed fiber that nobody joins. `start`: `done` reports the error (FIB:1099-1104).
# `racePair` loser: its race callback (FIB:934-935) counts as a listener, so the error is
# never reported, although nobody looks at the loser.
case("race-loser-error-lost",
     seq(race(op("pure", v=N(1)), seq(op("cede"), op("raise", code=5))),
         op("cede"), op("cede"), op("cede")))
case("start-error-reported",
     seq(op("start", e=seq(op("cede"), op("raise", code=5))), op("cede"), op("cede"), op("cede")))
for c in cases:
    print(json.dumps(c, separators=(",", ":")))
