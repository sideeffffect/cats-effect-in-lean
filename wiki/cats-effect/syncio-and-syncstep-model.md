# SyncIO and syncStep model (CE-0001)

> Sources: Cats Effect source at v3.7.1 (`SyncIO.scala`, `IO.scala:1161-1162`, `:2173-2178`, `:2340-2402`, `Sync.scala:52-62`, `MonadCancel.scala:593-611`, `AsyncLaws.scala:84-88`, `IOSuite.scala:2577-2700`); cats-core 2.13.0 (`Monad.scala:34-35`, `ApplicativeError.scala:105`); own Lean work and scala-cli runs, 2026-11-10
> Raw: [SyncIO and syncStep mirror notes](../../raw/cats-effect/2026-11-10-syncstep-mirror-notes.md); [Calibration reproducers notes](../../raw/cats-effect/2026-11-10-calibration-reproducers-notes.md); [Review 1 fixes notes](../../raw/project-decisions/2026-11-10-review1-fixes-notes.md)

## Overview

The first refuted property of the project. `IO#syncStep` uses `G = SyncIO`, whose root cancel scope is `Uncancelable`. Then `SyncStep.interpret` walks into `IO.Uncancelable` (body called with an identity `poll`) and past `IO.OnCancel` (finalizer dropped). If it stops later, the `Left` rest has no mask and no finalizer. `AsyncLaws.syncStepIdentity` fails. The Lean refutation and reproducer case 4 show the same defect. Status of the record: draft, waits for review.

## Files

| File | Content |
|---|---|
| `Model/SyncIO.lean` | `SVal` (adds `IO` and `SyncIO` values to `Val`), `SyncIO` (11 constructors, tag order), closures `SFn`/`SMap`, `SyncIO.runLoop` and `succeeded`/`failed` of `unsafeRunSync` |
| `Model/SyncStep.lean` | `SyncStep.interpret` with `G = SyncIO`, closure meaning `callS`, `syncStep`, `steppedRest`, observations `SyncStepObs.*` |
| `Model/SyncStepExamples.lean` | 11 checks: IOSuite `syncStep` tests (#2858, limit, error) and single branches |
| `Props/Calibration/SyncStep.lean` | `syncStepIdentitySyncIO` |
| `Proofs/Calibration/SyncStep.lean` | `syncStepIdentitySyncIO_refuted` |

## Mirror

- `SyncIO.runLoop`: all 11 tags (`SyncIO.scala:236-303`). `succeeded`/`failed` (`:305-345`) are mutually structural on `conts`; `mapK`, `flatMapK`, `handleErrorWithK` are inlined. Depth limit 512 in `mapK`. A fatal throw leaves `unsafeRunSync`. Fuel: one unit per iteration.
- The run loop takes a `SyncIOEnv` (how to apply a closure) as a parameter. `SyncStep.callS` gives the meaning.
- `SyncStep.interpret` (`IO.scala:2348-2402`): `limit <= 0`, `stepsUntilDefer <= 0` (`G.defer`), then `Pure`, `Error`, `Delay`, `RealTime`, `Monotonic`, `Map`, `FlatMap`, `Attempt`, `HandleErrorWith`, `Uncancelable` and `OnCancel` (guarded by `rootCancelScope == Uncancelable`), default `Left(io)`. Fuel: one unit per call.
- `G` operations as `SyncIO` nodes: `map` is `Monad.map` (`FlatMap` + `Pure`), `handleError` is `handleErrorWith(f andThen pure)`, `defer` is `flatMap(delay(t))(x => x)`.
- `IdPoll` goes to user code as `Val.poll 0 0`. Real `poll` ids start at 1.

## Property

`syncStepIdentitySyncIO`: for all user code `env`, programs `fa`, limits and initial `Ref` cells. Hypotheses (type invariants only): `WellFormed (fun _ => false) (refHandles refs) env fa` ([outcome equivalence](../semantics/outcome-equivalence.md), decision 27), and `initialRefsOK refs` (the initial cells hold no handles except `Ref` handles of these cells). Then:

- every claim-making direct run has a stepped run with the same observation, and
- every claim-making stepped run has a direct run with the same observation.

Direct = `fa` as root fiber. Stepped = `fa.syncStep(limit).unsafeRunSync()`, then `Left(io) => io`, `Right(a) => IO.pure(a)`, throw `=> IO.raiseError(e)`, as root fiber on the resulting heap. Runs use the single-fiber driver (`Solo`, `counterMaskModel`, default config) under a schedule `steps bs` (only `step` choices; `bs` gives the observe flags). Observation = (summary, `Ref` cells, emitted values). Out of fuel and model aborts make no claim.

No external cancel (decision 26). With it, a correct `syncStep` also failed the statement: a cancel before `run()` stops `fa`, but the `SyncIO` prefix of the stepped side already ran (review batch 1, entry 5). The single-fiber driver is allowed here (decision 23): `syncStep` is single-fiber, and the witness starts no fiber.

Decision: the statement uses run observations directly, because the shared `Eqv` (`Model/Enum.lean`) is not in this worktree. Rebase onto `Eqv` when it exists.

## Refutation

Counterexample (reproducer case 4): `IO.uncancelable(_ => IO.canceled *> flag.set(true))`, `limit = Int.MaxValue`, flag = `Ref` cell 0, initially `false`. User ids are `0, 2, 4` (even: the codec convention). The witness is well-formed (`cx_wellFormed`: `progOK` by `decide +kernel`, `CallOK` by cases on the id).

- Direct, 6 steps: `(Succeeded(()), [true], [])`.
- Stepped: `SyncIO` fuel < 6 is out of fuel; fuel `m + 6` gives the rest `IO.canceled.flatMap(_ => flag.set(true))` (`rfl` with free `m`). From the rest, 10 states are reachable. They are closed under all choices, and none shows the direct observation (`decide +kernel`).
- Closure argument: `cancel c` reads `c` only to take over a suspended fiber. The 10 states have no suspended fiber, so `cancel c` acts as `cancel 0`. The property has no `cancel` choices now, so this part is more than the proof needs.
- Re-run 2026-11-10 on 3.7.1: `REPRODUCED CE-0001` (4 / 4 cases differ).

Registry rows (decision 26): only the rows that the witness exercises: `core.IO.syncStep#2`, `core.IO.IOAsync.syncStep`, `core.SyncStep.MaxSteps`, `core.SyncStep.interpret#2`, `core.SyncIO.unsafeRunSync`. The 22 `core.SyncIO.tag.*` and `core.SyncIO.runLoop.*` rows are `todo` again. A "SyncIO always errors" mirror would also satisfy the refutation, so those rows need their own properties (for example the `SyncIO` monad and error laws). Decision 30: the `SyncIO`/`syncStep` mirror still needs difftest support before its rows pass review.

Wrong-function test: the fix of PR #4700 keeps the mask; its rest shows the direct observation, so `reach_obs` fails.

Ordinary inputs: the counterexample is an ordinary program (`uncancelable` with `canceled`, or `Resource.use`), so no separate "ordinary input" property is needed. The law with `G = F = IO` (inventory row `laws.AsyncLaws.syncStepIdentity`) is not covered; that row stays `todo`.

## Limits

- `Solo` runs one fiber. Programs with `start` are judged under a semantics where children do not run. The counterexample uses one fiber, so this does not matter for the refutation.
- `SyncIO.to[F]` (the reproducer's path) is not mirrored. `unsafeRunSync` is.
- Cases 1–3 of the reproducer (Resource, sleep, onCancel) need external cancel of a suspended fiber or `Sleep`. They are not proven in Lean.

## See Also

- [Cats Effect bug history and target areas](bug-history.md)
- [Run-loop model (single fiber)](runloop-model.md)
- [IO ADT and fiber state](io-adt-and-fiber-state.md)
- [Kernel evaluation of the model](../lean/kernel-evaluation.md)
- [Registry and audit](../methodology/registry-and-audit.md)
