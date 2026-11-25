"""Fixed cases for the format v2 ops of track P7D (Phase 7): `dUse`, `dSubmit`, `dForget`,
`dCancel`, `dPoll` (`std.Dispatcher` at v3.7.1, `parallel` and `sequential`, `await = true/false`).

Shapes (each for the four factories): a submission and a poll; `unsafeRunAndForget` of an effect
that raises (`reportFailure`); a cancel before the start and after the start (the effect waits on
a gate); an effect that cancels itself (its Future stays empty); an effect that never ends
(`await = false` cancels it, `await = true` blocks); a submission after the close
(`IllegalStateException`); CE-0090 (a submission while the release waits for a running effect);
CE-0091 (submit, then leave the scope at once); a follow-up submission from inside an effect;
small runtime thresholds; some pick choices.

The file name sorts after `supervisor.jsonl` on purpose: `CasesSuite` (sbt test) runs all case
files in one JVM in name order, and the `Supervisor` map order follows HotSpot identity hashes, a
per-thread sequence. These cases hash `Supervisor` tokens too, so run before `supervisor.jsonl`
they change that file's expected schedules (seen 2026-11-25).

Usage: python3 difftest/cases/gen_dispatcher.py   (writes track_p7d_dispatcher.jsonl; then
difftest/run.sh difftest/cases/track_p7d_dispatcher.jsonl > difftest/cases/track_p7d_dispatcher.expected.jsonl)
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
def attempt(e): return op("attempt", e=e)
def d_use(x, k, par, aw): return op("dUse", par=par, aw=aw, x=x, k=k)
def submit(e, d="d"): return op("dSubmit", d=V(d), e=e)
def forget(e, d="d"): return op("dForget", d=V(d), e=e)
def cancel(f): return op("dCancel", f=V(f))
def poll(f, x="o"): return bind(x, op("dPoll", f=V(f)), delay(1, V(x)))
def gate_get(g="g"): return op("deferredGet", d=V(g))
def gate_open(g="g", v=1): return op("deferredComplete", d=V(g), v=N(v))


CEDE = op("cede")
NEVER = op("never")
RT = [{"cancelationCheckThreshold": 1, "autoYieldThreshold": 2},
      {"cancelationCheckThreshold": 2, "autoYieldThreshold": 4}]
MODES = [(True, True), (True, False), (False, True), (False, False)]  # (par, aw)

cases = []


def case(id, prog, **k):
    c = {"v": 2, "id": id, "mode": "replay"}
    c.update(k)
    c["prog"] = prog
    cases.append(c)


def with_gate(body):
    return bind("g", op("deferredNew"), body)


for par, aw in MODES:
    m = f"p{int(par)}a{int(aw)}"
    U = lambda body: d_use("d", body, par, aw)
    # submit and poll
    case(f"disp-{m}-submit-poll", U(bind("f", submit(seq(emit(1), pure(N(42)))),
                                         seq(CEDE, CEDE, CEDE, poll("f"), pure(UNIT)))))
    # forget of an effect that raises: reportFailure
    case(f"disp-{m}-forget-raise", U(seq(forget(seq(emit(1), op("raise", code=7))), CEDE, CEDE, CEDE, pure(UNIT))))
    # submit an effect that raises: the Future holds the failure
    case(f"disp-{m}-submit-raise", U(bind("f", submit(op("raise", code=5)),
                                          seq(CEDE, CEDE, CEDE, CEDE, poll("f"), pure(UNIT)))))
    # cancel before the start
    case(f"disp-{m}-cancel-before", U(bind("f", submit(seq(emit(1), pure(N(3)))),
                                           bind("c", cancel("f"), seq(CEDE, CEDE, poll("c"), poll("f", "o2"), pure(UNIT))))))
    # cancel after the start (the effect waits on a gate; onCancel marker)
    case(f"disp-{m}-cancel-after", U(with_gate(bind("f", submit(op("onCancel", e=seq(emit(1), gate_get(), emit(2)), fin=emit(3), tag=1)),
        seq(CEDE, CEDE, CEDE, CEDE, bind("c", cancel("f"), seq(CEDE, CEDE, CEDE, CEDE, poll("c"), poll("f", "o2"))), gate_open(), CEDE, pure(UNIT))))))
    # an effect that cancels itself: its Future stays empty
    case(f"disp-{m}-self-cancel", U(bind("f", submit(seq(emit(1), op("canceled"))),
                                         seq(CEDE, CEDE, CEDE, poll("f"), pure(UNIT)))))
    # an effect that never ends
    case(f"disp-{m}-never", U(bind("f", submit(op("onCancel", e=seq(emit(1), NEVER), fin=emit(3), tag=2)),
                                   seq(CEDE, CEDE, pure(UNIT)))))
    # submission after the close (the dispatcher escapes the scope)
    case(f"disp-{m}-late", bind("e", U(pure(V("d"))), seq(attempt(submit(emit(9), d="e")), pure(UNIT))))
    # CE-0090: a submission while the release waits for a running effect
    case(f"disp-{m}-ce0090", bind("r", U(with_gate(bind("s", op("deferredNew"),
        bind("f1", submit(seq(op("deferredComplete", d=V("s"), v=N(1)), gate_get(), emit(2)) ),
            seq(op("deferredGet", d=V("s")),
                start(seq(op("sleep", ms=100), attempt(bind("f2", submit(seq(emit(5), pure(N(42)))),
                                                          seq(op("sleep", ms=10), poll("f2")))),
                          gate_open())),
                pure(UNIT)))))), seq(op("sleep", ms=1000), pure(UNIT))))
    # CE-0091: submit, then leave the scope at once (issue #3506 shape)
    case(f"disp-{m}-ce0091", bind("f", U(bind("f", submit(seq(emit(1), pure(N(7)))), pure(V("f")))),
                                  seq(op("sleep", ms=10), poll("f"), pure(UNIT))))
    case(f"disp-{m}-ce0091-forget", seq(U(forget(emit(1))), op("sleep", ms=10), pure(UNIT)))
    # a follow-up submission from inside an effect
    case(f"disp-{m}-nested", U(bind("f", submit(seq(emit(1), bind("f2", submit(seq(emit(2), pure(N(4)))),
                                                                     seq(CEDE, poll("f2", "i"))))),
                                     seq(CEDE, CEDE, CEDE, CEDE, CEDE, poll("f"), pure(UNIT)))))
    # several submissions, mixed modes, small runtime thresholds and some picks
    multi = U(seq(forget(emit(1)), bind("f", submit(seq(emit(2), CEDE, pure(N(1)))),
                                        seq(forget(emit(3)), CEDE, poll("f"), CEDE, CEDE, poll("f", "o2"), pure(UNIT)))))
    case(f"disp-{m}-multi", multi)
    for i, rt in enumerate(RT):
        case(f"disp-{m}-multi-rt{i}", multi, runtime=rt)
    case(f"disp-{m}-multi-picks", multi, choices=[1, 0, 2, 1, 0, 1, 1, 2, 0, 1])
    case(f"disp-{m}-cancel-after-picks", U(with_gate(bind("f", submit(seq(emit(1), gate_get(), emit(2))),
                          seq(CEDE, CEDE, bind("c", cancel("f"), seq(CEDE, CEDE, poll("c"))), gate_open(), pure(UNIT))))),
         choices=[0, 1, 1, 0, 2, 1, 0, 0, 1, 2])

(HERE / "track_p7d_dispatcher.jsonl").write_text("".join(json.dumps(c) + "\n" for c in cases))
print(f"{len(cases)} cases")
