# SyncIO and syncStep model (CE-0001)

> Sources: Cats Effect source at v3.7.1 (`SyncIO.scala`, `IO.scala:1161-1162`, `:2173-2178`, `:2340-2402`, `Sync.scala:52-62`, `MonadCancel.scala:593-611`, `AsyncLaws.scala:84-88`, `IOSuite.scala:2577-2700`); cats-core 2.13.0 (`Monad.scala:34-35`, `ApplicativeError.scala:105`); own Lean work and scala-cli runs, 2026-11-10
> Raw: [Review 2 fixes notes](../../raw/cats-effect/2026-11-10-review2-ce0001-ce0004-notes.md); [SyncIO and syncStep mirror notes](../../raw/cats-effect/2026-11-10-syncstep-mirror-notes.md); [Calibration reproducers notes](../../raw/cats-effect/2026-11-10-calibration-reproducers-notes.md); [Review 1 fixes notes](../../raw/project-decisions/2026-11-10-review1-fixes-notes.md)

## Overview

The first refuted property of the project. `IO#syncStep` uses `G = SyncIO`, whose root cancel scope is `Uncancelable`. Then `SyncStep.interpret` walks into `IO.Uncancelable` (body called with an identity `poll`) and past `IO.OnCancel` (finalizer dropped). If it stops later, the `Left` rest has no mask and no finalizer. `AsyncLaws.syncStepIdentity` fails. The Lean refutation and reproducer case 4 show the same defect. Review batch 2 found the statement HOLLOW (poll values observable, fatal errors in the domain). After decisions 37-39: polls are opaque, the statement is for non-fatal errors only, and a fixed twin of upstream PR #4700 satisfies it on a bounded domain. Status of the record: draft, waits for review.

## Files

| File | Content |
|---|---|
| `Model/SyncIO.lean` | `SVal` (adds `IO` and `SyncIO` values to `Val`), `SyncIO` (11 constructors, tag order), closures `SFn`/`SMap`, `SyncIO.runLoop` and `succeeded`/`failed` of `unsafeRunSync` |
| `Model/SyncStep.lean` | `SyncStep.interpret` with `G = SyncIO`, closure meaning `callS`, `syncStep`, `steppedRest`, observations `SyncStepObs.*` |
| `Model/SyncStepExamples.lean` | 11 checks: IOSuite `syncStep` tests (#2858, limit, error) and single branches |
| `Props/Calibration/SyncStep.lean` | `syncStepIdentitySyncIO`, `StepIdentityFor`, `NonFatalOnly`, `eraseObs` |
| `Proofs/Calibration/SyncStep.lean` | `syncStepIdentitySyncIO_refuted` |
| `Model/SyncStepFixed.lean` | fixed twin of PR #4700 (`interpretFixed`, `DeferredPoll`, `fixEnv`); not v3.7.1 |
| `Proofs/Calibration/StepCheck.lean` | finite check of `StepIdentityFor` (closed state lists) |
| `Proofs/Calibration/SyncStepTwinFamily.lean`, `SyncStepTwin.lean` | 10-program domain; `fixed_twin`, `v371_fails` |
| `Props/Calibration/FatalRaise.lean`, `Proofs/Calibration/FatalRaise.lean` | CE-0004 (`raiseErrorTwin`) |

## Mirror

- `SyncIO.runLoop`: all 11 tags (`SyncIO.scala:236-303`). `succeeded`/`failed` (`:305-345`) are mutually structural on `conts`; `mapK`, `flatMapK`, `handleErrorWithK` are inlined. Depth limit 512 in `mapK`. A fatal throw leaves `unsafeRunSync`. Fuel: one unit per iteration.
- The run loop takes a `SyncIOEnv` (how to apply a closure) as a parameter. `SyncStep.callS` gives the meaning.
- `SyncStep.interpret` (`IO.scala:2348-2402`): `limit <= 0`, `stepsUntilDefer <= 0` (`G.defer`), then `Pure`, `Error`, `Delay`, `RealTime`, `Monotonic`, `Map`, `FlatMap`, `Attempt`, `HandleErrorWith`, `Uncancelable` and `OnCancel` (guarded by `rootCancelScope == Uncancelable`), default `Left(io)`. Fuel: one unit per call.
- `G` operations as `SyncIO` nodes: `map` is `Monad.map` (`FlatMap` + `Pure`), `handleError` is `handleErrorWith(f andThen pure)`, `defer` is `flatMap(delay(t))(x => x)`.
- `IdPoll` goes to user code as `Val.poll 0 0`. Real `poll` ids start at 1.

## Property

`syncStepIdentitySyncIO`: for all user code `env`, programs `fa`, limits and initial `Ref` cells. Hypotheses: the type invariants `WellFormed (fun _ => false) (refHandles refs) env fa` ([outcome equivalence](../semantics/outcome-equivalence.md), decisions 27 and 37: polls are opaque) and `initialRefsOK refs` (the initial cells hold no handles except `Ref` handles of these cells), and the domain `NonFatalOnly env fa` (decision 38: only non-fatal errors are raised or thrown; fatal errors are CE-0004, section below). Then (`StepIdentityFor`):

- every claim-making direct run has a stepped run with the same observation, and
- every claim-making stepped run has a direct run with the same observation.

Direct = `fa` as root fiber. Stepped = `fa.syncStep(limit).unsafeRunSync()`, then `Left(io) => io`, `Right(a) => IO.pure(a)`, throw `=> IO.raiseError(e)`, as root fiber on the resulting heap. Runs use the single-fiber driver (`Solo`, `counterMaskModel`, default config) under a schedule `steps bs` (only `step` choices; `bs` gives the observe flags). Observation = (summary, `Ref` cells, emitted values), compared after `eraseObs` (every poll value becomes `Val.poll 0 0`: the two sides give the body different `Poll` objects by design). Out of fuel and model aborts make no claim.

No external cancel (decision 26). With it, a correct `syncStep` also failed the statement: a cancel before `run()` stops `fa`, but the `SyncIO` prefix of the stepped side already ran (review batch 1, entry 5). The single-fiber driver is allowed here (decision 23): `syncStep` is single-fiber, and the witness starts no fiber.

Decision: the statement uses run observations directly, because the shared `Eqv` (`Model/Enum.lean`) is not in this worktree. Rebase onto `Eqv` when it exists.

## Refutation

Counterexample (reproducer case 4): `IO.uncancelable(_ => IO.canceled *> flag.set(true))`, `limit = Int.MaxValue`, flag = `Ref` cell 0, initially `false`. User ids are `0, 2, 4` (even: the codec convention). The witness is well-formed (`cx_wellFormed`: `progOK` by `decide +kernel`, `CallOK` by cases on the id).

- Direct, 6 steps: `(Succeeded(()), [true], [])`.
- Stepped: `SyncIO` fuel < 6 is out of fuel; fuel `m + 6` gives the rest `IO.canceled.flatMap(_ => flag.set(true))` (`rfl` with free `m`). From the rest, 10 states are reachable. They are closed under all choices, and none shows the direct observation (`decide +kernel`).
- Closure argument: `cancel c` reads `c` only to take over a suspended fiber. The 10 states have no suspended fiber, so `cancel c` acts as `cancel 0`. The property has no `cancel` choices now, so this part is more than the proof needs.
- Re-run 2026-11-10 on 3.7.1: `REPRODUCED CE-0001` (4 / 4 cases differ).

Registry rows (decision 26): only the rows that the witness exercises: `core.IO.syncStep#2`, `core.IO.IOAsync.syncStep`, `core.SyncStep.MaxSteps`, `core.SyncStep.interpret#2`, `core.SyncIO.unsafeRunSync`. The `core.SyncIO.tag.*` and other `core.SyncIO.runLoop.*` rows are `todo` (`core.SyncIO.runLoop.Error` is now `modelled` through CE-0004). A "SyncIO always errors" mirror would also satisfy the refutation, so those rows need their own properties (for example the `SyncIO` monad and error laws).

Difftest (decision 30): format v1 covers the mirror. About 9.2 % of the 58,957 agreeing cases (about 5,400) have a root `syncStep` op, with the Lean harness (`unsafeRunSync()` on the caller thread, then the selected `IO`); the fixed cases `ss-ce0001-direct` and `ss-ce0001-stepped` agree. Weak point: the `limit + 1` mutation was killed by only 5 cases ([differential testing](../methodology/differential-testing.md)). Below the 50,000-per-op level.

Fixed twin (decision 39): `Model/SyncStepFixed.lean` mirrors PR #4700. `DeferredPoll` is `Val.poll 0 (d + 1)`; its `poll(io)` is `Local(unmask d).flatMap(applyK io)`, which applies the real `Poll` bound in the fiber's `IOLocal` state (list of `(d, poll)`). The rest is `Uncancelable(Bind(d, rest))`; `onCancel` rests are rewrapped; a non-fatal body throw becomes `raiseError`. On 10 non-fatal programs the twin satisfies `StepIdentityFor`, v3.7.1 fails 5 (`fixed_twin`, `v371_fails`). A poll after an async boundary works in the PR (it does not keep `IdPoll`); a fix that keeps `IdPoll` would fail program 2.

Ordinary inputs: the counterexample is an ordinary program (`uncancelable` with `canceled`, or `Resource.use`), so no separate "ordinary input" property is needed. Fatal errors are excluded (decision 38). The law with `G = F = IO` (inventory row `laws.AsyncLaws.syncStepIdentity`) is not covered; that row stays `todo`.

## Limits

- `Solo` runs one fiber. Programs with `start` are judged under a semantics where children do not run. The counterexample uses one fiber, so this does not matter for the refutation.
- `SyncIO.to[F]` (the reproducer's path) is not mirrored. `unsafeRunSync` is.
- A throw from an `uncancelable` body is modelled as `IO.raiseError(e)` on the stepped side. In Scala at v3.7.1 it leaves the `syncStep(limit)` call itself (review batch 2, minor point 4). Twin program 10 shows the difference.
- `WellFormed` is not proven for the 10 twin programs (Scala programs by construction). `PollOpaque` knows two poll kinds; the twin adds `DeferredPoll`.
- Cases 1–3 of the reproducer (Resource, sleep, onCancel) need external cancel of a suspended fiber or `Sleep`. They are not proven in Lean.

## CE-0004: fatal `raiseError`

`IOFiber.scala:263-269` calls `onFatalFailure` for `Error(fatal)` (PR #3811, issue #3767); `SyncIO.scala:257-259` has no check, so `SyncIO` `handleErrorWith` catches a fatal error. Through `syncStep` or `SyncIO#to[IO]` the same program meets both policies. Reproducer: `sio.unsafeRunSync()` = 1 and `sio.to[IO].syncStep(Int.MaxValue).unsafeRunSync()` = `Right(1)`, but `sio.to[IO].unsafeRunSync()` throws (3.7.1, `series/3.x`, `series/3.7.x`). Lean: `raiseErrorTwin` refuted (registry `core.SyncIO.runLoop.Error.fatalTwin`); the fixed twin `SyncIOEnv.fixFatalRaise` (throw a fatal error out of `unsafeRunSync`) holds on a bounded domain. Likely partly intended: maintainers keep fatal errors out of the laws (#549). Record: [CE-0004](../../bugs/CE-0004.yaml).

## See Also

- [Cats Effect bug history and target areas](bug-history.md)
- [Run-loop model (single fiber)](runloop-model.md)
- [IO ADT and fiber state](io-adt-and-fiber-state.md)
- [Kernel evaluation of the model](../lean/kernel-evaluation.md)
- [Registry and audit](../methodology/registry-and-audit.md)
