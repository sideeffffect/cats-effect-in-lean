# Track R: satisfiability witnesses and marker check (own note, decisions 53-54)

> Source: own work in this repository (`CatsEffectInLean/Proofs/Phase6/RaceWitness.lean`), Lean v4.35.0; review batch 4 (`review/2026-11-10-review-batch-4.md`, entries 9-11)
> Collected: 2026-11-10
> Published: 2026-11-10

- Witnesses (all `decide +kernel` runs plus a `WellFormed` proof of the sides with the statement's own `env`, user code `u0` = every call throws):
  - `combNoLeak`: `race(pure 1, never)`, FIFO: fiber 1 `Succeeded(1)`, loser fiber 2 `Canceled`, root done.
  - `combCanceledNoLeak`: `race(never, never)` in fiber 1, schedule `pick 0` ×3 then `preempt`: the parent's cancel lands while the race runs; fibers 1, 2, 3 `Canceled`.
  - `timeoutNoLeak`: `never.timeout(1)`, FIFO: root `Errored(TimeoutException)`, source `Canceled`, sleep `Succeeded`; parent form with the same preemption: source and sleep `Canceled`.
  - `raceOutcomeIsWinnerOutcome`: `raceOutcome(pure 1, never)`, FIFO: root `Succeeded(Left(Succeeded(1)))`.
- `WellFormed` user-code clauses: `env_calls` and `env_opaque` hold for every pair of sides (only the parent closures `PLam` run as user code).
- Decision 54: the statements read no user marker, only the fiber table and the root summary. A race child is made only by a `RacePair` that the racing fiber runs. User code cannot name a `ContState`, `poll` or fiber that it does not hold. No forgeable observation found.
- Wrong-function test now kernel-checked (`noCancel_leaks`: a `race` without `f.cancel` ends with live race child `[2]`). The old module doc named a file `Model/RaceSmoke.lean` that never existed; review batch 4 cited it. Fixed.
- Citation fix: `uncancelableRaceNotInherited` is `GenSpawnLaws.scala:146-147` (was `:121-122`).
