# Review batch 11a notes (2026-11-15)

Own notes of the independent reviewer. Full review: `review/2026-11-15-review-batch-11a.md`. Commit reviewed: `9f8a482` (`origin/main`), track Q (`Queue`, Phase 7). Read only; nothing was run.

## Verdicts

- FAITHFUL as statements: `std.Queue.Concurrent.noLoss`, `Async.noLoss`, `Concurrent.noDup`, `Async.noDup`, `Concurrent.noDeadlock`, `Async.noDeadlock`, `std.Queue.twinSeq` (low strength: one fiber).
- HOLLOW: `std.Queue.Concurrent.fifo`, `Async.fifo` (F1), `std.Queue.Concurrent.takerLiveness`, `Async.takerLiveness` (L1).

## Findings

- Mirrors: faithful, line by line, both families. The factory choice by capacity is correct (`1 < n < 65534` gives the `Async` class). Every `IODeferred.get` that the model builds with `none` is built in Scala before the `Deferred` is published, so `initial` is correct.
- Sequential consistency: stated in the `QueueAsync` module doc, the wiki and the registry notes. Each Scala `F.delay`/`F.defer` thunk is one model thunk; the shared `var`s are read on the same fiber after the write. No interleaving between separate thunks is hidden.
- No forgery channel: no statement has user code; elements are data and never run; trace events are built only by the harness. The v1 mirror `Std/Queue.lean` gives only data helpers (`Takers`, `notifyOne`) to the new mirrors.
- The atomic pattern `uncancelable(poll => poll(op).map(record))` is the CE test pattern (`QueueSuite.scala:793-812`). Inside `poll` every cancel point of `take` stays reachable; only the gap after `take` returned is removed.
- F1: "at most one taking script" is not a documented precondition. A wrong `take` that takes the last element when another taker waits (`wLastIfWaiters`) meets the statement (with one taking script the takers list is empty at that point) and breaks FIFO with three consumers. Fix: tag removal events with the script index; per-consumer, per-producer `Sublist`; drop the hypothesis.
- L1: "total takes <= total offers" counts canceled consumers. Every wakeup that a canceled taker absorbs has a spare offer. `AbstractQueue#offer` never waits while a taker waits, `UnboundedAsyncQueue#offer` never waits, so a queue without the cancel pass-on (`cleanup`, `notifyNextTaker`, `notifyAnyway`) meets the statement. The canonical lost wakeup `[[take], [take], [offer 1]]` (cancel the first woken taker) is outside the statement. Fix: put the condition into the conclusion (`blocked` only if all recorded offers are removed and every started offer returned).
- Fair schedules: `outcomesP` observes only halted runs; `blocked` means no ready task. So unfair schedules cannot fake a deadlock. A livelock is not observed.
- Difftest claims consistent: 66,000 = 3 x 22,000; 52,941 per op = 17,651 + 17,598 + 17,692; kind counts add to 52,941. Own RNG, appended scenario, no case deleted, no gate lowered.
- Low: D1 `isPublic` marks `QC.getState` public; it returns the whole state with taker `Deferred`s (a forged wakeup if user code is added later). D2 `UnsafeBounded`/`UnsafeUnbounded` rows are an SC specification, not a mirror; the helper exclusions "modelled as part of its public caller" do not apply. D3 gen.py was broken between merges `81cabbb`..`1e84acb`; no queue difftest run on the merged generator; latch and queue scenarios share the name base 20000. D4 no `selftest.py` coverage floor for `q*` ops. D5 livelock not covered.
