# race, both, raceOutcome, bothOutcome and fiber leaks

> Sources: Cats Effect v3.7.1 (`IO.scala:228-244`, `:638-642`, `:1729-1733`, `:1788-1789`, `:1996-2170`; `GenSpawn.scala:354-500`; `GenSpawnLaws.scala:121-122`); cats-core 2.13.0; own Phase 6 track R work, 2026-11-10
> Raw: [Track R notes](../../raw/cats-effect/2026-11-10-race-both-track-r-notes.md)

## Overview

Phase 6 batch 6.1, track R. Mirror of the four `GenSpawn` combinators for `IO`, difftest format v2, a fiber-leak observation, and five registered properties (all `open`). No bug candidate.

## Dispatch: no twin

`IOAsync` does not override `race`, `raceOutcome`, `both` or `bothOutcome`. Every `IO` entry point (`IO#race`, `IO.race`, `IO#both`, `IO.both`, `IO#raceOutcome`, `IO#bothOutcome`, `IO.bothOutcome`) ends in the kernel default. So there is no IO-vs-kernel twin for them. The mirror is the kernel body with the `IOAsync` operations put in.

## Files

| File | Content |
|---|---|
| `Model/Race.lean` | `RLam` (14 library closures, `Codec` namespace 10), `combIO k a b`, `raceIO`, `raceOutcomeIO`, `bothIO`, `bothOutcomeIO`, `call srcIO` |
| `Model/Leak.lean` | `liveRaceChildren`, `Sched.rootDone`, exact checker `leakFreeP` + `leakFreeP_sound` |
| `Props/Phase6/Race.lean` | `combNoLeak`, `combCanceledNoLeak`, `timeoutNoLeak`, `raceOutcomeIsWinnerOutcome`, `uncancelableRaceNotInherited`; env `dispatch` (race, timeout, parent closures namespace 11, user code) |
| `tools/LeakSmoke/Main.lean` | `lake exe leaksmoke [runs]`: random-schedule smoke test |
| `spikes/race-leak/LeakSmoke.scala` | same check on real CE 3.7.1 (`TestControl`) |

## Mirror rules

- `*>` = `flatMap(_ => that)`; `that` is built eagerly (`f.cancel`, `f.join` read the fiber when the `racePair` continuation runs).
- `as` = `map(_ => b)`; `onCancel` = `OnCancel`; `tupleLeft/Right` = `map`; `product` = `flatMap(fa)(a => map(fb)(b => (a, b)))` (cats `FlatMap`).
- `never` = `Timeout.neverIO` (`Async.never`).
- The sides `fa`, `fb` are closure fields as codes; the caller gives `srcIO : Val → IO` (as in `Model/Timeout.lean`).

## Leak observation

- `Obs` cuts at root completion and does not see live fibers (decision 33).
- `liveRaceChildren s r`: fibers without an outcome that still have a race callback (constructor slot 0) on a `ContState` of fiber `r`. These are the live children of a `racePair` that fiber `r` ran.
- Only the two `racePair` children count. Fibers that user code starts inside a side may outlive the combinator by design (fibers are not structured).
- Real runtime: the runner's `pending` (ready tasks + timers) does not show a fiber that waits forever. The visible proxy is a finalizer trace event of the side, or a counter of started-but-not-ended sides (the Scala spike).

## Properties (all `open`)

| Entry | Statement |
|---|---|
| `core.IO.race.combNoLeak` | root = combinator, all `WellFormed` sides, all user code and `PChoice` schedules: at root completion no live race child of fiber 0 |
| `core.IO.race.combCanceledNoLeak` | decision 50: a parent starts the combinator, cancels and joins it; no live race child of fiber 1 |
| `core.IO.timeout.noLeak` | `fa.timeout(d)`, direct and canceled by a parent |
| `core.IO.raceOutcome.isWinnerOutcome` | `Left(oc)` only if fiber 1 ended with `oc`; `Right(oc)` only if fiber 2 did |
| `laws.GenSpawnLaws.uncancelableRaceNotInherited.IO` | closed law under `EqvP` |

- Smoke evidence: `leaksmoke` 140,400 random runs, 0 violations; real CE 7,038 completed runs, 0 violations.
- Wrong-function test: a `race` without `f.cancel` leaks on `race(pure 1, never)` in every completed run.
- Why open: a proof for all sides needs an invariant over `Step`/`SchedP`: a racing fiber gets past its combinator only after both children are done. Exact search does not scale: the law's left side has more than 994 states (3 fibers, preemption at every iteration); `decide +kernel` of `checkEqvP` timed out after 8 min.

## Difftest

Format v2 ([program format](../methodology/difftest-program-format.md)): 225,000 generated cases over seeds 1–3, 0 mismatch; agreeing cases per op ≥ 50,782 (race 56,695, raceOutcome 50,782, both 58,367, bothOutcome 51,340). Tool: `difftest/py/opcount.py`.

Side effects on shared difftest code: `gen.py` weights for the v2 productions (default about 5–7 % of cases per op; `selftest.py` checks ≥ 5 %); the shrinker measure (`drive.measure`) counts `never` nodes before the JSON length, so a `never` can become `canceled` (the new generator mix made the selftest's mock shrink stop at size 8; now 3).

## See Also

- [Kernel typeclasses model](kernel-typeclasses-model.md)
- [Scheduler model](scheduler-model.md)
- [Queue and timeout model](queue-model.md)
- [Resource use, allocated, both, and CE-0020](resource-use-both-model.md) (`Resource#both` runs its finalizers with `GenSpawn#both`)
- [Outcome sets, Eqv and the IO laws](../semantics/outcome-equivalence.md)
- [Difftest program format](../methodology/difftest-program-format.md)
- [Registry and audit](../methodology/registry-and-audit.md)
