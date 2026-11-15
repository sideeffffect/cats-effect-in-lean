# Semaphore and Mutex model, CE-0060

> Sources: Cats Effect v3.7.1 (`std/.../Semaphore.scala:28-298`, `std/.../Mutex.scala:24-112`, `std/.../LockQueue.scala:24-110`, `kernel/.../Resource.scala:156-208`, `:388-397`, `:879-880`, `:942-944`, `:1229-1234`, `kernel/jvm-native/.../SyncRef.scala:30-95`, `kernel/.../Ref.scala:123-124`, `:208-250`, `IO.scala:1715-1720`, `:1822-1830`, `:1996-2180`, `IODeferred.scala:62-79`, `docs/std/mutex.md`); cats-core 2.13.0 (`cats/instances/queue.scala:136-138`, `cats/Traverse.scala:299-309`, `cats/Foldable.scala:591-596`, `cats/instances/option.scala:145-149`); PR #4648; own Phase 7 track S work and scala-cli runs, 2026-11-15
> Raw: [Track S notes](../../raw/cats-effect/2026-11-15-semaphore-mutex-track-s-notes.md)

## Overview

Phase 7, batch 7.1, track S. Mirrors of `Semaphore[IO]` and `Mutex[IO]` (with `LockQueue`), nine
difftest ops (format v2), eight registered statements. One is refuted: CE-0060, `count` counts
canceled waiters. Seven are `open`, each with a kernel-checked satisfiability witness and a
random-schedule smoke test with wrong-function checks.

## Implementations and twins

- `Semaphore` has one implementation (`impl`); `Semaphore.in` builds the same class. Since PR #4648
  (in v3.7.1) a canceled `acquireN` does not remove its request: it races its gate (`won`), and
  `reclaim` removes only the head; `releaseN` wakes or sweeps canceled requests later.
- `Mutex` at v3.7.1 has only `ConcurrentImpl` over `LockQueue.lock` (a CLH queue lock with
  `Deferred` cells, `Ref.access` + CAS). The `AsyncImpl` of earlier versions is gone. The twin is
  `Semaphore(1).permit` (`docs/std/mutex.md`: "Basically, it's a Semaphore with a single available
  permit").

## Files

| File | Content |
|---|---|
| `Model/Semaphore.lean` | Closures `SL` (namespace 60): `acquireN`, `releaseN` (`fulfil`, `wake`, `sweep`), `reclaim`, `tryAcquireN`, `available`, `count`, `permit.use` (the `fold` closures of `Resource` over `IO.bracketFull`), public `op*` closures |
| `Model/Mutex.lean` | Closures `ML` (namespace 61): `Mutex[IO]`, `LockQueue.lock` (`acquire` loop, `awakeCell` with `access`/CAS, `release`), `lock.use`; the dispatcher `Mutex.env` (SL, ML, `Bracket`) |
| `Props/Phase7/Semaphore.lean` | 8 statements; harness `HS` (62), behaviour tables `BH` (63), FIFO harness `FL` (64); `semLib` |
| `Proofs/Phase7/SemaphoreWitness.lean` | Satisfiability witnesses (decision 53) |
| `Proofs/Phase7/SemaphoreCount.lean` | `semCountAtRest_refuted` (CE-0060) |
| `Proofs/Phase7/SemaphoreCountFixed*.lean` | Fixed twin (closures `FX`, 65) and its kernel check (`TwinChecks`) |
| `tools/SemSmoke/Main.lean` | `lake exe semsmoke [runs]` |

## Mirror rules

- A lock object is a reference (`Val.fn`) to `SL.obj q` / `ML.obj q`. User code that holds it
  cannot reach the state `Ref` (decision 58, `WF.avail`): Scala keeps `state` private.
- Scala values of type `IO` inside the state transition (`await`, `releaseN(sunk)`, `wake *>
  sweep`) are descriptors (`cloVal 60 90..95`); `flattenK`/`thenK` rebuild them.
- `gate.get` and `nextCell.get` read the `Deferred` when the term is built (`IO.deferredGetOf` with
  the view of the building closure).
- `traverse_` of a `Queue` (`wake`) and of an `Option` (`sweep`) are mirrored with the cats-core
  2.13.0 instance bodies; the small-threshold difftest cases check the iteration counts.

## Difftest

Ops (format v2): `semNew n`, `semAcquireN s n`, `semReleaseN s n`, `semTryAcquireN s n`,
`semAvailable s`, `semCount s` (negative as `left`), `semPermit s e` (`permit.use(_ => I(e))`),
`mutexNew`, `mutexLock m e` (`lock.use(_ => I(e))`); handles `{"t":"sem"}`, `{"t":"mutex"}`. The
generator appends a `tpl_sem`/`tpl_mutex` scenario with its own RNG (`p_sem`).

| Ops | Cases, seeds | Result |
|---|---|---|
| Semaphore ops | 162,000, seeds 61-64 | 161,999 agree; per op ≥ 53,290 (`semTryAcquireN`), `semPermit` 100,897; 1 mismatch: a `parTraverseN` harness gap (below) |
| `mutexNew`, `mutexLock` | 78,000, seeds 71-76 | all agree; 51,304 cases with the ops |
| `cases/semaphore.jsonl` | 24 fixed cases | all agree (golden file) |

The one mismatch is in the `parTraverseN` part of a mixed case (a `HashSet` of 5 children whose
`f` starts fibers): `rankOrder` assumes consecutive child fiber ids, so the Lean `alternatives` miss
the order of that JVM run. The same case alone agrees. Mutation checks: a `reclaim` that keeps the
sunk permits, and a mutex waiter that hands on `EmptyCell`, give 5 and 10 mismatches in 1,500
cases.

## Properties

| Entry | Status | Claim |
|---|---|---|
| `std.Semaphore.noLostPermit` | open | all fibers ended → `available = k + released` (all `WellFormed` user code, cancels anywhere) |
| `std.Semaphore.noDeadlock` | open | behaviour tables, `need ≤ k`: every stopped run is `Succeeded`, `available = k + released` |
| `std.Semaphore.permit.atMostK` | open | at most `k` counted holders at once |
| `std.Mutex.lock.mutualExclusion` | open | at most one counted holder at once |
| `std.Mutex.lock.noDeadlock` | open | behaviour tables: every stopped run ends `Succeeded(())` (the lock is free at the end) |
| `std.Semaphore.count.atRest` | refuted (CE-0060) | all fibers ended → `count = available` |
| `std.Semaphore.acquireN.fifo` | open | strict FIFO: after `releaseN(r)` the longest prefix with sum ≤ r is served |
| `std.Mutex.lock.semaphoreTwin` | open | each (outcome, trace) of `Mutex` is one of `Semaphore(1)` |

Smoke (`lake exe semsmoke 40`): 13,920 stopped runs, 0 violations of the open statements; every
wrong function ('leak a permit', 'release twice', 'skip a waiter', 'LIFO', 'no wait', 'lost
wakeup', 'wide') breaks its claim; a forging user function is rejected by `WellFormed`. The random
inputs did not hit CE-0060 (it needs a non-head waiter canceled first and no later release); the
refutation is a fixed input.

Why open: a proof for all schedules needs a state invariant over `Step`/`SchedP` (for example
permits + held + sunk = k + released), as the open Phase 6 entries.

## CE-0060

`Semaphore(0)`; fibers `a`, `b` call `acquire`; cancel `b` (not the head: `reclaim` does nothing),
then `a` (the head: `reclaim` calls `releaseN(0)` = `F.unit`, no sweep). Nobody waits, but `count =
-1` until the next release. Priority low; likely intended (PR #4648 names the trade-off
"count may transiently include them"), but not transient without a later release. No permit is
lost. Lean: `semCountAtRest_refuted` (default schedule, fuel 92). Fixed twin (eager removal, as
v3.7.0): 4 inputs x 12 schedules (kernel) and the smoke test. Reproducer: v3.7.1, series/3.x,
series/3.7.x.

## Review (batch 11b, 2026-11-15)

- Mirrors faithful. CE-0060: FAITHFUL. As statements FAITHFUL: `noLostPermit`, `permit.atMostK`,
  `mutualExclusion`, `acquireN.fifo`, `semaphoreTwin` (one direction, stated).
- HOLLOW: `std.Semaphore.noDeadlock`, `std.Mutex.lock.noDeadlock`. `Base.err e` allows a fatal `e`;
  a fatal `raiseError` stops the run with `Summary.fatal`, so "every stopped run is `Succeeded`" is
  false for every implementation (`bus = [.permit 0 (.err { code := 0, kind := .fatal })]`, `as =
  [.join 0]`). Fix: a non-fatal hypothesis, or "not blocked" as the conclusion.
- Weakness: "`acquireN(n ≥ 2)` always raises" satisfies every `Semaphore` statement (`fifo`
  vacuously). Add a success clause to `noDeadlock`.
- The twin docstring sentence "the converse is the same claim ...; the smoke test samples both" is
  wrong: the smoke checks only mutex ⊆ semaphore.
- Source: [review batch 11b](../../review/2026-11-15-review-batch-11b.md).

## See Also

- [parTraverseN model](partraverse-model.md) (its `MiniSemaphore` got the same lazy cancelation in PR #4648)
- [Resource use, allocated, both](resource-use-both-model.md)
- [guarantee and bracket model](bracket-model.md)
- [Queue and timeout model](queue-model.md)
- [Difftest program format](../methodology/difftest-program-format.md)
- [Agent workflow](../methodology/agent-workflow.md)
