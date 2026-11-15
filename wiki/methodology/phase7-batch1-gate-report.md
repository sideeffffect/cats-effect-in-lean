# Phase 7 batch 7.1 gate report (2026-11-15)

> Sources: own gate summary from the registry, battery files, inventory, bug record CE-0060, difftest and smoke notes, and review batches 11a–14 (2026-11-15)
> Raw: [Review batch 14 notes](../../raw/project-decisions/2026-11-15-review-batch-14-notes.md); [Review batch 13 notes](../../raw/project-decisions/2026-11-15-review-batch-13-notes.md); [Decision 63](../../raw/project-decisions/2026-11-15-decision-63-wrong-function-battery.md); [Phase 7 start](../../raw/project-decisions/2026-11-15-phase7-start.md); [Queue review 13 battery](../../raw/cats-effect/2026-11-15-queue-review13-battery.md); [Semaphore/Mutex review 13](../../raw/cats-effect/2026-11-15-semaphore-mutex-review13.md); [Track L review 13 fix](../../raw/cats-effect/2026-11-15-track-l-review13-fix.md)

## Overview

Phase 7 batch 7.1 ran on 2026-11-15 in tracks Q (`Queue`, both families as twins), S (`Semaphore`, `Mutex`) and L (`CountDownLatch`, `CyclicBarrier`). Gate rule ([Project plan](project-plan.md), Phase 7): rows reviewed FAITHFUL. Decision 63 adds: each structure's wrong-function battery is complete. Phases 6–8 have no user gate; this report is the input for the review gate. Full review: `review/2026-11-15-review-batch-14.md`.

**Gate verdict (review batch 14, draft): FAIL**, one blocker (B1). All 33 entries are FAITHFUL as statements.

## Verdict table (all batch 7.1 registry entries)

An entry counts only if its latest verdict is FAITHFUL (FAITHFUL as a statement for an open entry).

| # | Entry | Status | Latest verdict | Batch |
|---|---|---|---|---|
| 1 | `std.Queue.Concurrent.noLoss` | open | FAITHFUL (statement) | 11a; re-checked 12–14 |
| 2 | `std.Queue.Async.noLoss` | open | FAITHFUL (statement) | 11a; 12–14 |
| 3 | `std.Queue.Concurrent.noDup` | open | FAITHFUL (statement) | 11a; 12–14 |
| 4 | `std.Queue.Async.noDup` | open | FAITHFUL (statement) | 11a; 12–14 |
| 5 | `std.Queue.Concurrent.fifo` | open | FAITHFUL (statement) | 12; 13–14 |
| 6 | `std.Queue.Async.fifo` | open | FAITHFUL (statement) | 12; 13–14 |
| 7 | `std.Queue.Concurrent.noDeadlock` | open | FAITHFUL (statement) | 11a; 12–14 |
| 8 | `std.Queue.Async.noDeadlock` | open | FAITHFUL (statement) | 11a; 12–14 |
| 9 | `std.Queue.Concurrent.takerLiveness` | open | FAITHFUL (statement) | 13; 14 |
| 10 | `std.Queue.Async.takerLiveness` | open | FAITHFUL (statement) | 13; 14 |
| 11 | `std.Queue.twinSeq` | open | FAITHFUL (statement, low strength) | 11a; 13–14 |
| 12 | `std.Queue.Concurrent.seqSpec` | open | FAITHFUL (statement) | 13; 14 |
| 13 | `std.Queue.Async.seqSpec` | open | FAITHFUL (statement) | 13; 14 |
| 14 | `std.Queue.Synchronous.tryHandoff` | open | FAITHFUL (statement) | 14 |
| 15 | `std.Semaphore.noLostPermit` | open | FAITHFUL (statement) | 11b; 12–14 |
| 16 | `std.Semaphore.noDeadlock` | open | FAITHFUL (statement) | 13; 14 |
| 17 | `std.Semaphore.permit.atMostK` | open | FAITHFUL (statement) | 11b; 12–14 |
| 18 | `std.Mutex.lock.mutualExclusion` | open | FAITHFUL (statement) | 11b; 12–14 |
| 19 | `std.Mutex.lock.noDeadlock` | open | FAITHFUL (statement) | 13; 14 |
| 20 | `std.Semaphore.count.atRest` (CE-0060) | refuted | FAITHFUL | 11b; record 14 |
| 21 | `std.Semaphore.acquireN.fifo` | open | FAITHFUL (statement) | 14 |
| 22 | `std.Mutex.lock.semaphoreTwin` | open | FAITHFUL (statement) | 11b; 12–14 |
| 23 | `std.CountDownLatch.awaitNotEarly` | open | FAITHFUL (statement) | 11b; 13–14 |
| 24 | `std.CountDownLatch.noLostWakeup` | open | FAITHFUL (statement) | 11b; 13–14 |
| 25 | `std.CountDownLatch.releaseTotal` | open | FAITHFUL (statement) | 11b; 13–14 |
| 26 | `std.CountDownLatch.awaitCompletes` | open | FAITHFUL (statement) | 14 (HOLLOW 13, H4) |
| 27 | `std.CountDownLatch.noDeadlock` | open | FAITHFUL (statement) | 14 |
| 28 | `std.CyclicBarrier.noEarlyTrip` | open | FAITHFUL (statement) | 11b; 13–14 |
| 29 | `std.CyclicBarrier.exactGenerations` | open | FAITHFUL (statement) | 11b; 13–14 |
| 30 | `std.CyclicBarrier.cancelNoHang` | open | FAITHFUL (statement) | 11b; 13–14 |
| 31 | `std.CyclicBarrier.cancelRemoved` | open | FAITHFUL (statement) | 11b; 13–14 |
| 32 | `std.CyclicBarrier.awaitCompletes` | open | FAITHFUL (statement) | 14 (HOLLOW 13, H4) |
| 33 | `std.CyclicBarrier.noDeadlock` | open | FAITHFUL (statement) | 14 |

## Battery coverage (decision 63)

| Structure | Rows (kernel-checked unless "meaningless") | Complete |
|---|---|---|
| Queue | 7 classes (`BoundedQueue`, `DroppingQueue`, `CircularBufferQueue`, `BoundedAsyncQueue`, `UnboundedAsyncQueue`, `DroppingAsyncQueue`, `Synchronous`) × `offer`, `tryOffer`, `take`, `tryTake` × {raises, hangs, drops, doubles}; `size` raises/hangs (drops/doubles meaningless: read); 7 factory kinds × raises/hangs (drops/doubles meaningless); `Synchronous` try hand-off by `tryHandoff` | yes, with condition C1 |
| Semaphore | `acquire`, `acquireN`, `release`, `releaseN`, `tryAcquire`, `tryAcquireN`, `permit` × 4; `available`, `count` raises/hangs/wrong value/contended; `apply` raises/hangs | **no** (B1) |
| Mutex | `lock` × 4; `apply` raises/hangs (drops/doubles meaningless) | yes |
| CountDownLatch | `release` × 4; `await` raises/hangs/drops (doubles meaningless: no effect on state); `apply` raises/hangs (drops/doubles meaningless); `mapK` not mirrored | yes |
| CyclicBarrier | `await` × 4; `apply` raises/hangs (drops/doubles meaningless); `mapK` not mirrored | yes |

Each break is a kernel run whose result is an element of `outcomesP` (or a `¬ XV v` theorem over the full statement for the latches); the v3.7.1 mirror meets the same claim on the same input (`good_*`, `*_mirror`, `v0_*`).

## Headline numbers

| Metric | Value |
|---|---|
| Batch 7.1 registry entries reviewed FAITHFUL (latest verdict) | 33 of 33 (as statements); structures with a complete battery: 4 of 5 |
| Settled: proven / refuted / open | 0 / 1 / 32 |
| Refutations with a bug record and a recorded `REPRODUCED` on v3.7.1 and series/3.x | 1 of 1 (CE-0060; also series/3.7.x) |
| Bug candidates that were not real (false positives) | 0 of 1 (CE-0060 `maybe_intended: likely`; Q5 open, default stands) |
| HOLLOW verdicts per batch (statement defects, before the fix) | 11a: 4/11, 11b: 2/15, 12: 2/26, 13: 2/30, 14: 0/33 (+1 battery gap) |
| Review batches in batch 7.1 | 5 (11a, 11b, 12, 13, 14) |
| Inventory rows `modelled` (only through settled entries) | 5 new (`std.Semaphore.count`, `acquireN`, `acquire`, `releaseN`, `apply`, through CE-0060) |

## Difftest (format v2) and smoke

| Structure | Cases, seeds | Result |
|---|---|---|
| Queue (`qNew`, `qOffer`, `qTryOffer`, `qTake`, `qTryTake`, `qSize`) | 66,000 (seeds 71–73) + 66,000 merged generator (seeds 81–83); 222 fixed cases | all agree; ≥ 52,838 agreeing cases per op; 15 kinds |
| Semaphore (7 ops) | 162,000 (seeds 61–64); merged 51,000 (seeds 101–103); 24 fixed | 161,999 agree: 1 mismatch in a `parTraverseN` part (harness `rankOrder`, fixed `b838472`; that batch then 5,000/5,000); merged run all agree |
| Mutex (`mutexNew`, `mutexLock`) | 78,000 (seeds 71–76) | all agree; 51,304 cases with the ops |
| Latches (`cdlNew`, `cdlRelease`, `cdlAwait`, `cbNew`, `cbAwait`) | 135,000 (seeds 71–73); 54 fixed | all agree; ≥ 56,600 agreeing cases per op |

Smoke: `qsmoke` (27,600 stopped runs on the merged generator, 0 violations; exhaustive one-fiber schedules), `semsmoke` (13,920 runs, 0 violations), `test/Phase7/LatchSmoke.lean` (0 violations of all statements; wrong variants violate). No mirror changed for `v = 0` after the difftests (review batch 14, C.2). Sources: [Queue families model](../cats-effect/queue-families-model.md), [Semaphore and Mutex model](../cats-effect/semaphore-mutex-model.md), [CountDownLatch and CyclicBarrier model](../cats-effect/latch-barrier-model.md).

## Bugs found in batch 7.1

| Bug | Kind | Priority | Lean | v3.7.1 | series/3.x | Fixed twin |
|---|---|---|---|---|---|---|
| CE-0060 `Semaphore#count` counts canceled waiters | doc mismatch | low | refuted (`semCountAtRest_refuted`) | REPRODUCED | REPRODUCED | eager removal (v3.7.0 behaviour): 4 inputs × 12 schedules (kernel), smoke |

Q5 (`QUESTIONS.md`): not answered. Default: keep CE-0060 as low priority, `maybe_intended: likely`, nothing filed upstream. The gate does not depend on the answer.

## Blockers

1. **B1 (track S): Semaphore battery incomplete.** Rule (a) of review batch 13: the "drops" variant of a try-operation is the honest one. A `tryAcquire`/`tryAcquireN` that always answers `false` (no effect) breaks no Semaphore or Mutex statement: the harness `tryRel` returns `()` in both branches, and no statement reads the answer. The battery rows use the dishonest drop (`true`). Fix: a statement that rejects the honest drop (for example a one-fiber sequential spec for `Semaphore`), kernel rows, mirror runs; re-review.

## Conditions (not blockers)

1. C1 (track Q): honest `tryOffer` drop rows (kernel) on the six non-`Synchronous` classes (`SeqSpec` rejects them by reading).
2. C2: CI green on the gate commit (run for `8325ca2` was pending at review time).
3. C3: another agent re-runs `reproducers/CE-0060` on v3.7.1 and series/3.x at the gate.
4. C4: `bugs/CE-0060.yaml` `status` comment still says "not reviewed yet" (reviewed FAITHFUL in batch 11b).
5. C5: inventory `registry` links for the Semaphore, Mutex and LockQueue rows of the 7 open track S entries.

## Open caveats

1. 32 of 33 entries are open. They need state invariants over `Step`/`SchedP` (queue state vs buffer, permits + held + sunk, latch state).
2. The `Async` queue family is modelled under sequential consistency (project plan, Phase 7 item 3). Weak-memory behaviour is deferred to Phase 9.
3. `tryHandoff` checks one schedule (FIFO replay), one partner and no cancel per input. A hand-off that races with a cancel is covered only by `noLoss`/`noDup` (all schedules).
4. The latch `noDeadlock` statements use user programs `IO.pure(())`; the other latch statements keep arbitrary `WellFormed` user code.

## See Also

- [Phase 6 gate report](phase6-gate-report.md)
- [Project plan](project-plan.md)
- [Agent workflow and review protocol](agent-workflow.md)
- [Differential testing](differential-testing.md)
- [Queue families model](../cats-effect/queue-families-model.md)
- [Semaphore and Mutex model](../cats-effect/semaphore-mutex-model.md)
- [CountDownLatch and CyclicBarrier model](../cats-effect/latch-barrier-model.md)
