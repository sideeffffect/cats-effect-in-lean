# Review batch 13 notes (2026-11-15)

Own notes of the independent reviewer. Full review: `review/2026-11-15-review-batch-13.md`. Commit reviewed: `05eecbb` (`origin/main`), diff base `6299201`. Read only; no build, test, difftest or `gh` call was run.

## Scope

Decision-63 batteries (Queue, Semaphore/Mutex, latches) and the changed or new batch 7.1 entries: queue `takerLiveness` (both, `JoinsSucceeded`), new `seqSpec` (both), Semaphore and Mutex `noDeadlock` ("`Succeeded …` or `fatal`"), new `awaitCompletes` (latch and barrier), the latch mirror variants.

## Findings

- A battery row `runObsP … = some o` is an element of `outcomesP` by definition (`obs` is `some` only for result summaries), so each kernel row is a real break of the statement with the wrong environment. The Bool forms (`specB`, `liveB`, `c2`, `c5`, ...) match the Props by reading.
- Queue: H3 and W3 closed (join event tag 7, only `QH.joinRec` emits it, no user code). `SeqSpec` is a faithful reading of the Scaladoc capacity rules plus code details (dropping `tryOffer` `false`, circular `tryOffer` `true`, `Synchronous` `size` 0). 53 battery rows kernel-checked with mirror runs on the same inputs.
- G1 (open, track Q): besides `Synchronous#tryTake` drops, an honest `Synchronous#tryOffer` drop (always `false`) passes every statement. The battery used a dishonest drop (`true`), which `SeqSpec` catches.
- Semaphore/Mutex: H2 and W2 closed. 38 rows kernel-checked with `good_*` mirror runs. "Wrong value" for reads is more than the rule asks; fair for constant offsets.
- O1: no statement reads `available` while a fiber waits. A wrong `available` that is wrong only under contention passes statements 1-7 by reading.
- Latches: mirror unchanged for `v = 0`; `X ↔ XV 0` by `Iff.rfl`; breaks are `¬ XV v` theorems over the full statement (strongest form). 6 of 11 rows have no kernel mirror run on the same input (L4).
- H4 (HOLLOW): `cdlAwaitCompletes`, `cbAwaitCompletes` say "if the root is done"; a root `Errored` is done. A `CountDownLatch.apply` / `CyclicBarrier.apply` that always raises stops every run before any fiber starts and meets every latch statement. The battery has no `apply` row. Same pattern as batch 12 H2.
- Missing factory rows in the Queue and Semaphore tables are low: a raising factory breaks `SeqSpec` / `noDeadlock` by reading.

## Batch 7.1 status

30 entries. Latest verdict HOLLOW: `std.CountDownLatch.awaitCompletes`, `std.CyclicBarrier.awaitCompletes` (H4). FAITHFUL: the other 28. G1 open (track Q).

## Rules proposed

- For a try-operation, the battery "drops" variant is the honest one (`false`, `None`).
- The battery includes the factories. A success claim conditioned on "the root is done" must also claim that the root `Succeeded`.
