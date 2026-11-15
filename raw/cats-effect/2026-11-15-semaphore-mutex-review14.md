# Track S: batch 7.1 gate review (review batch 14) items (notes, 2026-11-15)

Own work after `review/2026-11-15-review-batch-14.md` (gate FAIL on B1 = G2; all 8 track S entries
FAITHFUL as statements).

## B1 (G2): the honest `tryAcquire`/`tryAcquireN` drop broke nothing

- The harness `tryRel n` returns `()` whatever `tryAcquireN` answers, and no statement read the
  answer. The battery used the dishonest drop (`true`, nothing taken), so rule (a) of review batch
  13 was not applied.
- New statements (`Props/Phase7/Semaphore.lean`, namespace 67, harness `SQ`):
  - 9 `std.Semaphore.seqSpec` (`semSeqSpec`): one fiber runs any script of `acquireN`, `releaseN`,
    `tryAcquireN`, `available`, `count`, `permit.use(_ => available)`; every answer is recorded; the
    answers equal `semSpec` and the run ends `Succeeded(())` or `blocked` exactly where the spec
    blocks (`acquireN`/`permit` without enough permits).
  - 10 `std.Mutex.lock.seqSpec` (`mutexSeqSpec`): `lock.use` on a free lock succeeds; a nested
    `lock.use` deadlocks (`Mutex.scala:41-42`).
- Check by evaluation: the model meets statement 9 on all 585 scripts of length ≤ 3 over 8 ops
  (`acq 1`, `acq 2`, `rel 1`, `tryAcq 1`, `tryAcq 2`, `avail`, `count`, `permit`), for each
  `k ∈ {0, 1, 2}`, and statement 10 on `[lock, lock, lockNested]`, `[lock, lock]`, `[]`.
- Witnesses (decision 53): `semSeqSpec_satisfiable` (answers `true` then `false`, then blocks),
  `mutexSeqSpec_satisfiable` (two locks, then the nested deadlock), `Proofs/Phase7/SemaphoreWitness.lean`.
- Battery rows (kernel): `tryAcquire_honestDrop` (`Semaphore(1)`, `[tryAcq 1, avail]`: answers
  `false` where the spec says `true`), `tryAcquireN_honestDrop` (`Semaphore(2)`, `[tryAcq 2, avail]`);
  v3.7.1 meets the spec on both inputs (`good_honestDrop_inputs`).
- Rule (a) for the other operations: `acquire`, `acquireN`, `release`, `releaseN`, `permit`,
  `lock` return `()`, so the drop has no answer to lie about; their "drops" rows are already honest.
  `available`, `count` are reads (no drop). The factories have no drop.

## C3, C4, C5

- C3: the CE-0060 reproducer re-run 2026-11-15T21:33Z (by track S; the gate may want an independent
  re-run): v3.7.1 and series/3.x (3.7.1-89-de84c01, head still `de84c01` by `gh api`): same output,
  `REPRODUCED CE-0060`.
- C4: `bugs/CE-0060.yaml` status comment names the reviews (11b, 13, 14) and Q5.
- C5: the `registry` column of the 14 Semaphore, Mutex and LockQueue inventory rows of the track S
  entries lists every entry that names the row.
