# Queue families model (Phase 7, track Q)

> Sources: Cats Effect v3.7.1 (`std/.../Queue.scala:31-1206`, `UnsafeUnbounded.scala:23-113`, `QueueSource.scala:23-80`, `kernel/jvm-native/.../SyncRef.scala`, `kernel/.../Ref.scala:123-124`, `IO.scala:1353-1431`, `:1548`, `:1996-2163`, `IOFiber.scala:225-260`, `:1210-1266`, `tests/.../QueueSuite.scala:787-890`); own Lean work, difftest and smoke runs, 2026-11-15
> Raw: [Review 14 honest drops](../../raw/cats-effect/2026-11-15-queue-review14-honest-drops.md); [Review 13 battery](../../raw/cats-effect/2026-11-15-queue-review13-battery.md); [Synchronous tryTake handoff](../../raw/cats-effect/2026-11-15-queue-sync-trytake-handoff.md); [Review 12 fixes and battery](../../raw/cats-effect/2026-11-15-queue-review12-battery.md); [Review batch 12 notes](../../raw/project-decisions/2026-11-15-review-batch-12-notes.md); [Review 11a fixes](../../raw/cats-effect/2026-11-15-queue-review11a-fixes.md); [Review batch 11a notes](../../raw/project-decisions/2026-11-15-review-batch-11a-notes.md); [Track Q results](../../raw/cats-effect/2026-11-15-queue-track-q-results.md); [Track Q notes](../../raw/cats-effect/2026-11-15-queue-track-q-notes.md); [Phase 7 start](../../raw/project-decisions/2026-11-15-phase7-start.md); [Review batch 13 notes](../../raw/project-decisions/2026-11-15-review-batch-13-notes.md)

## Overview

Phase 7, track Q (decisions 59-62). `std/Queue.scala` has two implementation families, mirrored side by side as twins:

- `Concurrent` (needs only `GenConcurrent`): `AbstractQueue` with `BoundedQueue`, `DroppingQueue`, `CircularBufferQueue` (state in one `Ref`, waiters as `Deferred`s), and `Synchronous` (two-phase commit with latches).
- `Async` (lock-free): `BaseBoundedAsyncQueue` with `BoundedAsyncQueue`, `DroppingAsyncQueue` (buffer `UnsafeBounded`, waiter lists `UnsafeUnbounded` of callbacks), and `UnboundedAsyncQueue`.

For `IO` the factories pick the family by the capacity: `bounded(n)` is `BoundedAsyncQueue` for `1 < n < 65534`, `BoundedQueue` for `n = 1` or `n >= 65534`, `synchronous` for `n = 0`; `dropping(n)` likewise; `circularBuffer` is always `Concurrent`; `unbounded` is `UnboundedAsyncQueue`.

Result: mirrors of both families, difftest agreement, 11 open statements with kernel-checked witnesses and wrong-function tests, and random-schedule smoke with 0 violations. No bug found under sequential consistency.

## Files

| File | Content |
|---|---|
| `Std/QueueConcurrent.lean` | `AbstractQueue` (offer, tryOffer, take, tryTake, size, cleanups, `notifyNextTaker`), the three subclasses (`onOfferNoCapacity`, `onTryOfferNoCapacity`), `Synchronous`; closures `QC` (namespace 50) |
| `Std/QueueAsync.lean` | `BaseBoundedAsyncQueue` (take, tryTake, size), `BoundedAsyncQueue` (offer, tryOffer), `DroppingAsyncQueue`, `UnboundedAsyncQueue`; closures `QA` (namespace 52); sequential-consistency note |
| `Std/QueueFactory.lean` | Factories for `F = IO` (`newIO`), one op interface over both families, `env`, `isPublic` |
| `Props/Phase7/Queue.lean` | Harness (namespace 54), trace readers, 11 statements |
| `Proofs/Phase7/QueueWitness.lean` | Satisfiability witnesses (decision 53), kernel-checked runs |
| `Proofs/Phase7/QueueWrongFunction.lean` | 10 wrong functions, kernel-checked runs that break each claim (and the mirror meets it) |
| `tools/QSmoke/Main.lean` | `lake exe qsmoke [cases] [runs] [seed]`, `qsmoke wrong`, `qsmoke demo` |

## Mirror rules

- The queue object is a closure reference `Val.fn o` whose value holds the class, the capacity and the state cells. Every method lambda captures `this` as `Val.fn o`. User code that holds the queue cannot read or write the state cells (decision 58, `WF.avail`). Calling the object as a function is a non-fatal model error (no Scala analogue). The older v1 mirror `Std/Queue.lean` gives user code the buffer `Ref` itself; it stays for CE-0003 and the v1 ops only.
- `modify` returns `F[F[...]]`; the inner `F` is a descriptor value, and `flattenK` builds its term. The strict argument of `*>` is rebuilt by `thenD`.
- `SyncRef.modify`/`update`/`get` are one `Delay` thunk (atomic CAS). `flatModify` = `uncancelable(_ => flatten(modify(f)))`.
- All `Deferred.get` terms in the queues are built on a fresh `Deferred`, so they read `initial`.
- `UnsafeBounded` and `UnsafeUnbounded` under **sequential consistency**: each thunk is one atomic step. This is a model simplification (plan Phase 7 item 3): races inside a thunk on the JVM are out of scope until a weak-memory model exists (Phase 9).
- Capacities are `Nat`; `dropping(0)` and `circularBuffer(0)` throw before an `IO` exists, so they are outside the model.

## Statements (all open)

Harness: `rootIO k scripts plan mode`. Fibers run scripts of `offer`, `tryOffer`, `take`, `tryTake`, `size`, `cede`; each op runs as `uncancelable(poll => poll(op).map(record))`, the atomic pattern of QueueSuite "not lose data on canceled take". The plan cancels fibers after some `cede`s. Mode `cancelAll` cancels every fiber, mode `join js` joins some first; then the root drains with `tryTake`. All inputs are data, all `PChoice` schedules (preemption at any run-loop iteration). No user code, so no `WellFormed` hypothesis.

| Entry | Claim |
|---|---|
| `std.Queue.Concurrent.noLoss` / `Async.noLoss` | a run that ends `Succeeded` removes every recorded offered element (kinds that never drop) |
| `...noDup` | removed elements are a sub-multiset of offered elements (all kinds) |
| `...fifo` | every remover (each script, the drain) removes each producer's elements in offer order (Scaladoc `Q:31-33`); events carry the script index |
| `...noDeadlock` | mode `cancelAll`: every run that stops ends `Succeeded` |
| `...takerLiveness` | producers and consumers only, consumers joined: every run that stops ends `Succeeded`, or `blocked` with nothing to give (`QuietBlock`: every recorded offer removed, every started offer returned) |
| `std.Queue.Concurrent.seqSpec` / `Async.seqSpec` | one fiber, any script: trace and summary equal the sequential FIFO specification of the factory (decision 63) |
| `std.Queue.twinSeq` | `(boundedForConcurrent(cap), bounded(cap))`, `(droppingForConcurrent(cap), dropping(cap))`, `(unboundedForConcurrent, unbounded)` give the same (summary, trace) results for one fiber |

Each entry: witness (`QueueWitness`), wrong function (`QueueWrongFunction`, kernel-checked; `qsmoke wrong`), smoke (`qsmoke`).

Scope of the quantification: the queue state is private (the object reference), and a queue never calls user code, so a user program acts on a queue only through method calls in fibers, canceled at any point; the harness quantifies over exactly these (all scripts, plans, schedules). Each call runs in the atomic pattern that the CE test suite checks (`QueueSuite.scala:793-850`); a plain `take` that is canceled after it returned loses its value by definition, and a `take` inside `timeout` or `race` is the CE-0003 shape (#4571), so these are not in the statements. The atomicity of `take` under cancel is not in the Scaladoc; its source is that test (an undisputed invariant).

Review batch 11a ([review](../../review/2026-11-15-review-batch-11a.md)): `noLoss`, `noDup`, `noDeadlock`, `twinSeq` FAITHFUL as statements. `fifo` HOLLOW: the hypothesis "at most one taking script" is not documented; fix: tag removal events with the script index and state per-consumer, per-producer order. `takerLiveness` HOLLOW: the count hypothesis counts canceled consumers, so the cancel pass-on (`cleanup`, `notifyNextTaker`, `notifyAnyway`) is not tested for `AbstractQueue` and `unbounded`; fix: `blocked` only if every recorded offer is removed and every started offer returned. `takerLiveness` sees `blocked` runs only, not a livelock.

Fixes of review batch 11a (2026-11-15):

- F1 (`fifo`): each event carries its script index; `Fifo` states the order per remover (`removedBy`, the drain is its own remover) and per producer, with no "one taker" hypothesis. New wrong functions `wLastIfWaiters` (`AbstractQueue#take` takes the last element when another taker waits) and `wLastIfWaitersAsync`: three consumers, one producer, plan `[(1, 1)]`: consumer 0 removes `2` then `1` (kernel-checked; the mirror meets the claim on the same input). The old single-script inputs of `wLifo`/`wLifoConc` now take twice in one script.
- L1 (`takerLiveness`): no count hypothesis. The harness records `offerStart x` before `poll(offer(x))`, and a `blocked` stop is allowed only as `QuietBlock`. New wrong functions `wNoPassOn` (no `cleanup`/`notifyNextTaker` pass-on) and `wNoAnywayU` (no `notifyAnyway`): `[[take], [take], [offer 1]]`, plan `[(1, 0)]`, join `[0, 1]`: blocked with element 1 in the queue (kernel-checked; the mirror ends `Succeeded`).
- D1: `QC.getState` is not public any more (it returns the takers' `Deferred`s); user programs under `WellFormed` with `isPublic` cannot call the `Concurrent` `size` (no statement uses `isPublic`).
- D2: the `UnsafeBounded`/`UnsafeUnbounded` `put`/`take`/`size` rows are out of the track Q entries (the model is a sequentially consistent list, a specification, not a mirror of the CAS code); the excluded helper rows (`buffer`, `sequenceBuffer`, `head`, `tail`, `LookAheadStep`, `project`, `first`, `last`) now have the reason `deferred: phase 9 (weak memory model)`. `std.UnsafeUnbounded.put`/`take` stay `modelled` through the older CE-0003 entry.
- Re-run on the merged generator (seeds 81-83 × 22,000): 66,000 agree, 52,838 agreeing cases per queue op; `qsmoke 600 20 11`: 27,600 stopped runs, 0 violations; all 15 wrong functions break their claims.
- D3: the queue template has its own name base (40000; latch 20000, semaphore 30000). D4: `selftest.py` has a floor for the six queue ops. D5: livelock is not seen (registry notes and the statement doc).

Fixes of review batch 12 (2026-11-15):

- H3/W3: the harness records each join outcome (event 7); `TakerLiveness` (both families) also claims `JoinsSucceeded`: every joined consumer that the plan does not cancel ends `Succeeded`. `wSyncTakeRaises` (a `Synchronous#take` that raises) breaks it (kernel-checked).
- New statements `std.Queue.Concurrent.seqSpec`, `std.Queue.Async.seqSpec` (`SeqSpec`): one fiber, any script; trace and summary equal a sequential FIFO specification with the factory's capacity rule (`specRun`). This is the success claim of decision 63 item 3 for all five operations.
- Decision 63 battery: for `offer`, `tryOffer`, `take`, `tryTake`, `size` × raises, hangs, drops, doubles, a kernel-checked break in each family (`QueueBatteryConc`: `BoundedQueue`; `QueueBatteryAsync`: `BoundedAsyncQueue`; `QueueBatterySync`: `Synchronous`). `size` drops/doubles are meaningless (read only). The `Synchronous#tryTake` "drops" row (None while an offerer waits) is closed by statement 8, `std.Queue.Synchronous.tryTakeHandoff` (FIFO schedule: the offerer is registered when `tryTake` runs; Scaladoc and `Q:347-353` hand the element over; kernel-checked break `sync_tryTake_drops`). A per-run claim over all schedules cannot see this row: a `tryTake` before the offerer registers correctly returns `None` with the same observation. Table: [raw note](../../raw/cats-effect/2026-11-15-queue-review12-battery.md).
- The two `FailureSignal` rows: `deferred: phase 9 (weak memory model)`.

Review batch 13 (all 13 queue entries FAITHFUL; 2026-11-15 follow-ups):

- G1: statement 8 is `syncHandoff` (entry `std.Queue.Synchronous.tryHandoff`): both `tryTake` with a waiting offerer and `tryOffer` with a waiting taker (FIFO schedule). `wSyncTryOfferFalse` (always `false`) breaks it (kernel-checked).
- L1: the operation battery also runs on `DroppingQueue`, `CircularBufferQueue`, `UnboundedAsyncQueue`, `DroppingAsyncQueue` (`QueueBatteryConcOther`, `QueueBatteryAsyncOther`, every row kernel-checked).
- L2: factory rows (`QueueBatteryFactory`): seven factory kinds × raises, hangs break `SeqSpec`. Full table: [raw note](../../raw/cats-effect/2026-11-15-queue-review13-battery.md).

Review batch 14 C1 (2026-11-15): battery variant `dropsHonest` (`tryOffer` always `false`, `tryTake` always `None`, no effect) breaks `SeqSpec` on all six non-`Synchronous` classes (`QueueBatteryHonest`, 12 kernel-checked theorems); `Synchronous` is covered by `syncHandoff`.

Open points: proofs need invariants over `SchedP` runs (as the Phase 6 entries). No linearizability statement yet (only the sequential twin and FIFO). `mapK` (`Q:51-58`, open issue #4483), `tryTakeN`/`tryOfferN`, `unsafeBounded`, `unsafeUnbounded` are not mirrored.

Review batch 12 ([review](../../review/2026-11-15-review-batch-12.md)): both `fifo` entries FAITHFUL (per remover, per producer). The new events (script index, `offerStart` inside the mask) do not change the meaning of `noLoss`, `noDup`, `noDeadlock`, `twinSeq`. `Concurrent.takerLiveness` HOLLOW: the root ignores the join outcome of each consumer, so a `Synchronous#take` that always raises meets every `Concurrent` statement (`twinSeq` has no `synchronous` pair). `Async.takerLiveness` FAITHFUL with the same weakness (`twinSeq` catches it). Fix: record the join outcomes and claim `Succeeded` for the joined consumers that the plan does not cancel. Low: the two `FailureSignal` inventory rows keep "modelled as part of its public caller".

## Difftest (format v2)

Ops `qNew {kind, cap}`, `qOffer`, `qTryOffer`, `qTake`, `qTryTake`, `qSize` ([format](../methodology/difftest-program-format.md)). Fixed cases `queue2.jsonl` (222, every kind, cancels at several points, atomic takes, small runtime thresholds, external cancel): all agree on the first run. Generated (`opcount.py --seeds 71 72 73 --n 22000 --boost tpl_queue2=11`, own RNG stream, about 20 % with small runtime thresholds): 66,000 of 66,000 cases agree; each of the six ops is in 52,941 agreeing cases (17,598 to 17,692 per seed). Kinds in these cases: `bounded(2)` 5,931, `synchronous` 5,904, `bounded(1)` 5,824, `unbounded` 5,755, `unboundedConc` 3,899, `dropping(2)` 3,849, `circularBuffer(2)` 3,847, `boundedConc(2)` 3,806, `bounded(3)` 3,798, `bounded(0)` 2,018, `dropping(1)` 1,942, `circularBuffer(1)` 1,935, `boundedConc(1)` 1,904, `droppingConc(2)` 1,903, `bounded(70000)` 626. No model bug was found: every case agreed on the first run.

## Smoke

- `qsmoke 300 20 1`: 600 harness inputs (safety and liveness), 11,040 stopped runs, 0 violations. `qsmoke 1500 30 7`: 3,000 inputs, 84,210 stopped runs, 0 violations. The twin loop (statement 6) was added after these runs: `qsmoke 40 8 3`, 0 violations.
- `qsmoke exact [bound]`: exhaustive over every `PChoice` schedule (`outcomesPList`, sound by `outcomesPList_sound`) for one-fiber inputs that the root cancels at every point (`[take]`, `[offer 1, offer 2]`, `[offer 1, take]`): 0 violations for every kind checked (8 to 11 observations each, 4-55 s each). Inputs with two fibers (three with the root) do not close within 3,000 states.
- `qsmoke wrong`: all 11 wrong-function checks break their claims; the mirror meets them.

## Review (batch 13, 2026-11-15)

[Review](../../review/2026-11-15-review-batch-13.md). FAITHFUL: both `takerLiveness` (H3/W3 closed; only `QH.joinRec` emits tag 7), both `seqSpec` (Scaladoc capacity rules; one fiber), the other 9 entries (meaning unchanged). The battery (53 kernel rows, mirror runs on the same inputs) is correct. Gap G1 is wider than recorded: an honest `Synchronous#tryOffer` drop (always `false`) also passes every statement; the battery row used a dishonest drop (`true`). Low: the battery runs on one class per family; factories have no row.

## See Also

- [Queue and timeout model (CE-0003)](queue-model.md)
- [parTraverseN model](partraverse-model.md)
- [Differential testing](../methodology/differential-testing.md)
- [Agent workflow and review protocol](../methodology/agent-workflow.md)
- [Bug history](bug-history.md)
