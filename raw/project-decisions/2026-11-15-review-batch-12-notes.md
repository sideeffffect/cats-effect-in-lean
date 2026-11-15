# Review batch 12 notes (2026-11-15)

Own notes of the independent reviewer. Full review: `review/2026-11-15-review-batch-12.md`. Commit reviewed: `6299201` (`origin/main`), diff base `9f8a482`. Read only; no build, test, difftest or `gh` call was run.

## Scope

Re-review of the entries that changed after batches 11a and 11b: track Q `fifo` and `takerLiveness` (both families) and the effect of the new events on the 7 other queue statements; track S `noDeadlock` (both) and the join record (W1) in all track S statements; track G `rankOrder` model change (ghost list `all`, order input `ho all xs`) in the 8 `parTraverseN` statements.

## Findings

- Queue `fifo` (both): FAITHFUL. Per remover and per producer is the observable FIFO claim; a remover's record order is its dequeue order (masked record after `poll(take)`). Wrong functions `wLastIfWaiters*` are the 11a counterexample, kernel-checked.
- Queue harness change (script index, `offerStart` inside the mask before `poll`): no change of meaning for `noLoss`, `noDup`, `noDeadlock`, `twinSeq`.
- Queue `takerLiveness`: `QuietBlock` closes 11a L1. But the root ignores join outcomes (`QH.joinNext`). H3: `Synchronous#take` that always raises (`QC.sTakeK` throws) meets `concTakerLiveness` and every `Concurrent` statement; `twinSeq` has no `synchronous` pair. `Concurrent` HOLLOW. `Async` FAITHFUL with weakness W3 (`twinSeq` covers all `AsyncKeep` kinds).
- Semaphore `noDeadlock`: H1 (fatal) and W1 fixed. H2: the new conclusion "not `blocked`" plus claims on `Succeeded` allows a root `Errored`. `available` that always raises (`SL.availK` throws) makes every root `Errored`; no `Semaphore` statement catches it; the first form did. HOLLOW. Fix: "`Succeeded …` or `fatal`".
- Mutex `noDeadlock`: same form, weakness W2; the twin catches "`lock` raises" (root `Errored` is no `Semaphore(1)` outcome). FAITHFUL.
- Join record: only `HS.joinRec` emits tag 62; it is not public; statements 2 and 5 run `env behaved` (no user code). No forgery. The record holds the use outcome, which user code could already emit, so the twin cannot become false; it gets stronger. CE-0060 input has no `join`.
- parTraverseN: the new order input contains every old one (`fun _ xs => o xs`), so the statements are stronger and still an over-approximation; `all` is read only by `setToList`; the 8 statements stay FAITHFUL.
- D1-D5 done. Low D2a: the two `FailureSignal` rows keep "modelled as part of its public caller", but the callers are not modelled by track Q.

## Batch 7.1 status

24 of 26 Phase 7 entries have FAITHFUL as the latest verdict. HOLLOW: `std.Queue.Concurrent.takerLiveness` (H3), `std.Semaphore.noDeadlock` (H2).

## Rule proposed

A liveness statement whose root joins fibers must read the join outcomes. A conclusion that excludes only `blocked` must say why a root `Errored`/`Canceled` is allowed; for inputs where no root operation can raise, state "`Succeeded` or `fatal`".
