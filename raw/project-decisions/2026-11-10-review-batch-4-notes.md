# Review batch 4: verdicts on 13 Phase 6 registry entries (own note)

> Source: independent read-only review in this repository (`CatsEffectInLean/Registry.lean`, `Props/Phase6/{Memoize,Bracket,Race}.lean`, `Proofs/Phase6/*.lean`, `Proofs/Lemmas/Frame.lean`, `Model/{Memoize,Bracket,Race,Leak,WellFormed,Sched}.lean`, `bugs/CE-0005.yaml`, `bugs/CE-0030.yaml`, `reproducers/CE-0005/Repro.scala`, `reproducers/CE-0030/Repro.scala`, `inventory/inventory.csv`, wiki, review batches 1–3); Cats Effect source at v3.7.1 (`IO.scala`, `IODeferred.scala`, `GenConcurrent.scala`, `Ref.scala`, `MonadCancel.scala`, `GenSpawn.scala`, `GenSpawnLaws.scala`, `MonadCancelLaws.scala`); `origin/series/3.x` `GenConcurrent.scala`; read-only `gh search` (memoize, bracketFull). Full review: `review/2026-11-10-review-batch-4.md`.
> Collected: 2026-11-10
> Published: 2026-11-10

## Verdicts

- FAITHFUL:
  - CE-0030 `memoize.noStuckGet` (refuted, with caveats).
  - CE-0005 `bracketFull.kernelDefaultTwin` (refuted, low strength).
  - These open entries, as statements: `kernelDefaultTwin.pureUse`, `guaranteeIsGuaranteeCase.IO`, `race.combNoLeak`, `race.combCanceledNoLeak`, `timeout.noLeak`, `raceOutcome.isWinnerOutcome`, `uncancelableRaceNotInherited.IO` (citation fix required), `memoize.getsAgree`, `memoize.atMostOnce`.
- HOLLOW: `bracket.releaseOnce` and `guarantee.finalizerOnce`. Their hypotheses are unsatisfiable, so the statements are vacuous.

## Findings

- CE-0030:
  - The statement reads the memo cell, which is internal state. It is still a sound observation: `Finished` is written only after `fa` ends, and after that every correct `get` path completes.
  - The harness `get` fibers are unmasked, so a hang is a bug and not the correct masked behaviour.
  - User code cannot write the cell or forge a `get`, because both need the `.ref 0` handle.
  - The witness is `WellFormed` and reachable through the public API.
  - Limit: the Lean fixed-twin check uses only `fa = IO.canceled`.
- CE-0005: the mirrors and the fixed twin (`poll(IO.defer(use(a)))`) are correct. The input is a throwing `use`, which the kernel comment expects.
- Vacuity of the track-G marker invariants:
  - `BLam.thenUse m a` (and `dropOc m`) is a `good` library closure for every even `m`.
  - `LibEnv` forces that closure to forward the marker's effects. Its odd id is outside `ms`, so `MarkersOnly` clause 1 fails.
  - In `bracketReleaseOnce`, `rel` must be even, because `BLam.good (.dropOc rel)` is `userId rel`. But the hypothesis that `rel` returns a program naming `mR` contradicts `MarkersOnly` clause 2.
  - If clause 1 only checked even ids, user code could re-run a marker through such a wrapper, or through a forged `guaranteeIO (.ext f)`. The statement would then be false for a correct `guarantee`.
  - Fix: markers that user code cannot forge (closures that capture a harness handle), plus a Lean witness that the hypotheses are satisfiable.
- Leak notion (`Model/Leak.lean`): a fiber with no outcome that still holds a slot-0 `racePair` callback. It catches "never cancel the loser" and "cancel without join".
- `fiberOutcome` indexing by position is correct, because `finish` writes `fibers.set fib.id`.
- `Props/Phase6/Race.lean:190` cites `L/GenSpawnLaws.scala:121-122`. The law is at `:146-147`.
- The frame lemmas F1/F2 are about the real `tickP`/`runSchedStateP` and have no hypotheses.
- Inventory:
  - Only settled entries mark rows `modelled` (correct).
  - The registry column is missing for the bracket/guarantee rows.
  - `finalizerOnce` lists `kernel.MonadCancel.guarantee`, which it does not mirror.
