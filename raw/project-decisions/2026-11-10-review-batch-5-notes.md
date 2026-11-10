# Review batch 5: verdicts on 4 Phase 6 track Res (`Resource`) registry entries (own note)

> Source: independent read-only review of commit `3e553ed` (`CatsEffectInLean/Registry.lean`, `Props/Phase6/Resource.lean`, `Props/Phase6/Bracket.lean`, `Proofs/Phase6/ResourceBoth.lean`, `Model/{ResourceUse,Resource,WellFormed}.lean`, `test/Phase6/ResourceSmoke.lean`, `bugs/CE-0020.yaml`, `reproducers/CE-0020/Repro.scala`, `inventory/inventory.csv`, wiki, review batch 4, decisions 53–54); Cats Effect source at v3.7.1 (`Resource.scala`, `GenSpawn.scala`, `IO.scala`); `origin/series/3.x` `Resource.scala`; read-only `gh search` (Resource both, finalizer, parTupled). Full review: `review/2026-11-10-review-batch-5.md`.
> Collected: 2026-11-10
> Published: 2026-11-10

## Verdicts

- HOLLOW as registered: CE-0020 `kernel.Resource.both.releaseOnce` (refuted). The mirror is good, the bug is real and public (`Resource#both`, `parTupled`), the witness is genuine and has no forgery. But a correct `both` also refutes the statement.
- HOLLOW: `kernel.Resource.use.releaseOnce`, `kernel.Resource.flatMap.releaseOrder` (open). False for every implementation; no Lean satisfiability witness; the smoke instances do not satisfy `MarkedMake` (`resOf := none`).
- FAITHFUL as a statement: `kernel.Resource.eval.preservesCancelable` (open). One direction only (decision 41); "always `IO.canceled`" passes it, the companion CE-0002 entry catches that. Smoke part 3 writes `alloc` by hand, not with `allocatedCase`.

## Main finding: `UserMarkersOnly` is forgeable

- `usesId` compares only direct `Fn.user` ids. It does not decode the fields of an odd library closure.
- User code can return `.map (.pure ()) (ULam.allocFn (.user mR)).fn`. The closure calls `U.r.user.callV mR`, which is the release marker. `WellFormed` accepts it (odd, `isLib`, no captured handle). Both clauses of `UserMarkersOnly` hold.
- So `count R = count A + 1` is possible for every implementation. Other vectors: `ULam.allocFn (.make acq rel)`, `Bracket.BLam.thenUse`, Phase 5 `Clo` closures, and `a0`.
- This is the second half of the batch-4 `MarkersOnly` finding. Batch 4 found the strict form vacuous. The relaxed form (user ids only) is satisfiable but forgeable. Decision 54 (harness-only handle) is the fix.

## Inventory

- `both`, `use`, `fold` are used by the CE-0020 statement. `makeCase` and `evalMap` appear only as instances inlined in `both` (no general mirror), so they should not be `modelled`.
- All five rows should go back to `todo` until CE-0020 passes review.

## Required fixes

1. Harness-only markers (decision 54) or a deep closure-aware `usesId`.
2. Re-prove CE-0020 under the new hypothesis (the witness has no forgery).
3. Lean satisfiability theorems for `use.releaseOnce` and `flatMap.releaseOrder` (with and without the parent).
4. Smoke instances must satisfy and evaluate the hypotheses; compute `alloc` with `allocatedCase`.
5. Inventory as above.
6. Recommended: the CE-0020 reproducer prints `REPRODUCED` only if the fixed copy misses no release.

## Duplicate search (2026-11-10)

`gh search issues` on typelevel/cats-effect: `Resource both release error`, `both finalizer cancel`, `parallel finalizers error`, `Resource both leak` (no result); `parTupled` (#4620, #4497, #2238, #2197, #1652, #1576, #1645: none is CE-0020). `gh search prs`: `Resource both` (#3307, #3227, #3226, #2084, #1689 and others), `Resource both finalizers` (no result).
