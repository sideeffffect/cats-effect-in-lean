# Review batch 14 notes (2026-11-15)

Own notes of the independent reviewer. Full review: `review/2026-11-15-review-batch-14.md`. Commit reviewed: `8325ca2` (`origin/main`), diff base `5a360df` (batch 13). Read only; no build, test or difftest. One read-only `gh run list` (CI status).

## Scope

Fixes after batch 13 (track Q: `syncHandoff`, battery on all queue classes, factory rows; track S: factory rows, FIFO root reads `(available, count)` under contention, contended variants; track L: restated `awaitCompletes`, new `noDeadlock` statements, `apply` rows, v3.7.1 runs on battery inputs) and the Phase 7 batch 7.1 gate.

## Findings

- `std.Queue.Synchronous.tryHandoff` FAITHFUL as a statement. The FIFO replay schedule is a choice of test input: over all schedules the registration of the partner is not observable (`Synchronous#size` is 0). With no cancel in the input, every schedule after registration gives the hand-off (one `Ref`, atomic `flatModify`). G1 closed.
- `std.Semaphore.acquireN.fifo`: statement text unchanged, root stronger: every spin read must be `(0, -prev)` or `(0, -target)`. True for v3.7.1 by reading `S:182`, `:196-201`, `:256-263`. No cancel, so CE-0060 does not apply; `fulfil` (`S:212-225`) gives `count = r - Σ` at the end. O1 closed.
- Latch `awaitCompletes` (both) FAITHFUL: `1 ≤ n` / `1 ≤ cap` is the `apply` precondition; a done root is `Succeeded(())` for v3.7.1 (the root ignores join outcomes; fatal is not `done`). H4 closed.
- Latch `noDeadlock` (both) FAITHFUL: "at least `n` releasers" / "`cap * g` awaiters" are the promise's own conditions; "user programs `IO.pure(())`" removes only user-side blocking; CDL keeps all awaiter cancels; CB "no cancels" is covered by `cancelNoHang`/`cancelRemoved`.
- **G2 (new, blocker):** rule (a) not applied in the Semaphore battery. A `tryAcquire`/`tryAcquireN` that always answers `false` with no effect breaks no Semaphore or Mutex statement: `tryRel` returns `()` in both branches; no statement reads the answer. The rows use the dishonest drop (`true`).
- C1 (low): the queue `tryOffer` "drops" rows on six classes still use the dishonest drop; `SeqSpec` rejects the honest one by reading.
- C5 (low): the inventory `registry` column is empty for the Semaphore/Mutex/LockQueue rows of the 7 open track S entries.

## Gate

33 entries, all FAITHFUL as statements; proven / refuted / open 0 / 1 / 32. CE-0060 record complete (v3.7.1, series/3.x, series/3.7.x `REPRODUCED`); its status comment is outdated. Q5 unanswered; the default stands. Batteries complete for Queue (C1), Mutex, CountDownLatch, CyclicBarrier; incomplete for Semaphore (G2). Gate: FAIL, blocker B1 = G2.

## Rule proposed

- When a try-operation's answer is not read by any statement (the harness branches on it and returns the same value), the honest drop passes. Each try-operation needs a statement that reads its answer in a state where the answer is fixed (one fiber, or a fixed schedule).
