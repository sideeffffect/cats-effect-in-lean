"""Fixed cases for the format v2 queue ops (Phase 7, track Q).

`qNew` with every kind (`bounded`, `dropping`, `circularBuffer`, `synchronous`, `unbounded` and
the `Concurrent` twins `boundedConc`, `unboundedConc`, `droppingConc`), then `qOffer`,
`qTryOffer`, `qTake`, `qTryTake`, `qSize`: sequential use, a blocked taker woken by an offer, a
blocked offerer woken by a take, a canceled taker and offerer (at several points), the atomic
take pattern `uncancelable(poll => poll(take).flatMap(emit))` canceled by the parent, and the
synchronous handshake.

Usage: python3 difftest/cases/gen_v2_queue.py   (writes queue2.jsonl)
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
def emitR(e): return bind("r", e, emit(V("r")))  # run e, emit its result


CEDE = op("cede")
Q = V("q")
cases = []


def case(id, prog, **k):
    c = {"v": 2, "id": id, "mode": "replay"}
    c.update(k)
    c["prog"] = prog
    cases.append(c)


KINDS = [("bounded", 1), ("bounded", 2), ("bounded", 3), ("bounded", 0), ("dropping", 1), ("dropping", 2),
         ("circularBuffer", 1), ("circularBuffer", 2), ("synchronous", 0), ("unbounded", 0),
         ("boundedConc", 1), ("boundedConc", 2), ("unboundedConc", 0), ("droppingConc", 2)]


def withQ(kind, cap, body): return bind("q", op("qNew", kind=kind, cap=cap), body)


for kind, cap in KINDS:
    k = f"{kind}{cap}"
    # sequential: offers that do not block, then tryTake / size / tryOffer
    if kind != "synchronous" and not (kind == "bounded" and cap == 0):
        case(f"q-seq-{k}", withQ(kind, cap, seq(
            op("qOffer", q=Q, v=N(1)), emitR(op("qSize", q=Q)), emitR(op("qTryOffer", q=Q, v=N(2))),
            emitR(op("qTryTake", q=Q)), emitR(op("qSize", q=Q)), emitR(op("qTryTake", q=Q)),
            emitR(op("qTryTake", q=Q)))))
    # a waiting taker is woken by an offer
    case(f"q-wake-taker-{k}", withQ(kind, cap, bind("f", op("start", e=emitR(op("qTake", q=Q))), seq(
        CEDE, op("qOffer", q=Q, v=N(7)), op("join", f=V("f"))))))
    # two takers, two offers
    case(f"q-two-takers-{k}", withQ(kind, cap, bind("f", op("start", e=emitR(op("qTake", q=Q))),
        bind("g", op("start", e=emitR(op("qTake", q=Q))), seq(
            CEDE, op("qOffer", q=Q, v=N(1)), op("qOffer", q=Q, v=N(2)), op("join", f=V("f")), op("join", f=V("g")))))))
    # a producer that blocks on a full queue, woken by takes
    prod3 = seq(op("qOffer", q=Q, v=N(1)), op("qOffer", q=Q, v=N(2)), op("qOffer", q=Q, v=N(3)), emit(N(99)))
    case(f"q-wake-offerer-{k}", withQ(kind, cap, bind("f", op("start", e=prod3), seq(
        CEDE, CEDE, emitR(op("qTryTake", q=Q)), emitR(op("qTryTake", q=Q)), CEDE, emitR(op("qTryTake", q=Q)),
        emitR(op("qTryTake", q=Q)), op("cancel", f=V("f")), emitR(op("qSize", q=Q))))))
    # a canceled taker (cancel lands after c cedes), then an offer and a drain
    for c in range(3):
        case(f"q-cancel-taker-{k}-{c}", withQ(kind, cap, bind("f", op("start", e=emitR(op("qTake", q=Q))), seq(
            *([CEDE] * c), op("cancel", f=V("f")), emitR(op("qTryOffer", q=Q, v=N(5))), emitR(op("qTryTake", q=Q))))))
    # a canceled offerer (blocks on a full or synchronous queue)
    for c in range(3):
        case(f"q-cancel-offerer-{k}-{c}", withQ(kind, cap, bind("f", op("start", e=prod3), seq(
            *([CEDE] * c), op("cancel", f=V("f")), emitR(op("qTryTake", q=Q)), emitR(op("qTryTake", q=Q)),
            emitR(op("qTryTake", q=Q)), emitR(op("qSize", q=Q))))))
    # the atomic take pattern of QueueSuite "not lose data on canceled take", canceled by the parent
    take_rec = op("uncancelable", poll="p", body=op("poll", poll="p", e=emitR(op("qTake", q=Q))))
    for c in range(4):
        case(f"q-atomic-take-{k}-{c}", withQ(kind, cap, bind("f", op("start", e=seq(take_rec, take_rec)), seq(
            op("qTryOffer", q=Q, v=N(1)), *([CEDE] * c), op("qTryOffer", q=Q, v=N(2)), op("cancel", f=V("f")),
            emitR(op("qTryTake", q=Q)), emitR(op("qTryTake", q=Q))))))
    # with small runtime thresholds (auto-yield inside the queue code)
    case(f"q-preempt-{k}", withQ(kind, cap, bind("f", op("start", e=seq(emitR(op("qTake", q=Q)), emitR(op("qTake", q=Q)))),
        bind("g", op("start", e=seq(op("qOffer", q=Q, v=N(1)), op("qOffer", q=Q, v=N(2)), op("qOffer", q=Q, v=N(3)))), seq(
            CEDE, op("cancel", f=V("f")), op("cancel", f=V("g")), emitR(op("qTryTake", q=Q)), emitR(op("qTryTake", q=Q)))))),
        runtime={"cancelationCheckThreshold": 1, "autoYieldThreshold": 3})
    # external cancel of the root while it waits on take
    case(f"q-ext-cancel-{k}", withQ(kind, cap, emitR(op("qTake", q=Q))), choices=[0, 0, {"cancel": 0}, 0])

(HERE / "queue2.jsonl").write_text("".join(json.dumps(c, separators=(",", ":")) + "\n" for c in cases))
print(f"queue2.jsonl: {len(cases)} cases")
