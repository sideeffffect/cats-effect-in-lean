# Review batch 15 notes (2026-11-15)

Own notes of the independent reviewer. Full review: `review/2026-11-15-review-batch-15.md`. Commit reviewed: `1339812` (`origin/main`), diff base `8325ca2` (batch 14). Read only; no build, test or difftest. One read-only `gh run list` (CI status) and one read-only inventory/registry comparison script.

## Scope

Re-check of the Phase 7 batch 7.1 gate after review batch 14: B1 (= G2), conditions C1-C5.

## Findings

- `std.Semaphore.seqSpec` (statement 9) FAITHFUL as a statement. One fiber, a script of `acquireN`, `releaseN`, `tryAcquireN`, `available`, `count`, `permit.use(_ => available)`; every answer is recorded and compared as a whole list; the run ends `Succeeded(())` or `blocked` where the spec blocks. The spec follows the Scaladoc: `S:31-34`, `S:58` (blocking), `S:41-43` with `S:79-80` (`tryAcquireN` is `false` only when the count is too low), `S:39`, `S:50`, `S:105-109`. `outcomesP` drops `outOfFuel`/`taskLimit`; `PChoice` has no cancel. True for v3.7.1 by reading.
- `std.Mutex.lock.seqSpec` (statement 10) FAITHFUL as a statement. The nested deadlock is documented: `Mutex.scala:41-42` ("not reentrant, thus this `mutex.lock.surround(mutex.lock.use_)` will deadlock").
- B1 closed. The honest-drop rows replace `.delay (SL.modTry s n).fn` (the whole `tryAcquireNIO` for `n ≥ 1`) by `pure false`: no effect, rule (a). Kernel rows break statement 9; the mirror meets it on the same inputs.
- Rule (a) on all other mirrored Semaphore/Mutex operations: no unbroken honest drop. `tryPermit` is a public try-operation but not mirrored (`todo`); it is missing from the battery table's "not mirrored" list (low N2).
- C1 closed (12 kernel rows, breaks at the answer). C4 closed. C5 closed (0 differences in both directions over 10 entries).
- C2 open: CI run for `1339812` pending. C3 open: the independent CE-0060 re-run is with another agent; only the track S self re-run is recorded.

## Gate

35 entries (33 + 2 new), all FAITHFUL as statements; proven / refuted / open 0 / 1 / 34. All five batteries complete. Gate: PASS, open conditions C2 and C3.

## Lesson

- A one-fiber sequential statement is a cheap way to make every answer of a structure observable. It closes rule (a) for try-operations without a new concurrency claim.
- When a battery table lists "not mirrored" operations, check the inventory for every public method of the class, including derived ones in the abstract class (`tryPermit`).
