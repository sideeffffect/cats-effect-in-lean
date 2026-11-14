# Review batch 7: parTraverseN (batch 6.3) and the heavy-proof CI split (own note)

> Source: independent read-only review of commit `5132899` (`Model/ParTraverse.lean`, `Props/Phase6/ParTraverse.lean`, `Proofs/Phase6/ParTraverseWitness.lean`, `tools/PtSmoke/Main.lean`, `Model/WellFormed.lean`, `Model/Outcomes.lean`, `Registry.lean`, `RegistryHeavy.lean`, `Proofs/Phase6/RaceLaw.lean`, `Proofs/Lemmas/CertP.lean`, `tools/Audit/*.lean`, `scripts/check_heavy_proofs.sh`, `scripts/test_audit.sh`, `.github/workflows/{ci,paranoid,paranoid-heavy}.yml`, `difftest/py/{gen,selftest}.py` diffs vs `543528b`, the difftest Scala and Lean op); Cats Effect v3.7.1 (`GenConcurrent.scala:126-249`, `MiniSemaphore.scala`, `IODeferred.scala`, `IO.scala`, `Async.scala:168`, `GenSpawnLaws.scala:146-147`); cats-core 2.13.0 sources jar (`instances/list.scala`, `Traverse.scala`). Full review: `review/2026-11-14-review-batch-7.md`.
> Collected: 2026-11-14
> Published: 2026-11-14

## Verdicts

- HOLLOW: `core.IO.parTraverseN.resultOrder` (open). False for every implementation: user `f` is held only as a number (`k1` field, `TL.tag` field), so `WF.captured f` is never checked; an `f` that captured `.deferred r` (the internal result `Deferred`) completes it with a forged pair, and the mirror returns it.
- HOLLOW: `core.IO.parTraverseN.pureSucceeds` (open). Only defect: `as.length ≤ 4` (model limit for Scala `Set1`..`Set4`) is not a documented precondition. It does not remove the interesting case.
- HOLLOW: `core.IO.parTraverseN.errorAborts`, `.cancelAborts` (open). The limit, and all sibling actions fixed to `IO.never`: this keeps the sharpest test of "immediately abort" but removes completing siblings, late errors, two errors, and suspended `f(a0)`.
- FAITHFUL (low strength): `laws.GenSpawnLaws.uncancelableRaceNotInherited.IO` (proven, heavy). `race = never` also satisfies the law itself. Doc citation in `RaceLaw.lean:7` still `:121-122`.

## Other findings

- Mirror of `GenConcurrent#parTraverseN` is faithful branch by branch; many line citations drift 2-8 lines (list in the review).
- Satisfiability witnesses: all four kernel-checked, types hold all hypotheses together.
- Difftest: no case deleted; no self-test gate lowered (only a new 2 % gate); generator appends with its own RNG.
- Coverage gap: no statement checks "at most `n` at once"; an implementation that ignores `n` passes all four.

## CI split (decision 55)

- Checks: every old check runs on every push in one of the two jobs; the main audit never counts a deferred row as settled, but it passes with one (needs `heavy-proofs` required, Q4).
- Gap 1 (regression): heavy modules build outside the bwrap sandbox of `lake check`; build-time code could alter the audit tool or inventory before `audit_heavy` runs.
- Gap 3: module list and `#print axioms` list in `check_heavy_proofs.sh` are hard-coded to the `RaceLaw` family; a new heavy module would not be replayed by `leanchecker`.
- Gap 4: `paranoid-heavy.yml` exports only the root module; if `leanexport` has `leanchecker`'s per-module scope, the chunks are not replayed. Not verified.

## Lesson

- The batch 6 hidden-handle pattern (a closure id stored as a number escapes `WF.captured`) also hits user functions passed to library mirrors as `.nat` fields. Any statement with arbitrary user code and a library closure that stores the user id as a number needs a check of the user closure's captured handles.
