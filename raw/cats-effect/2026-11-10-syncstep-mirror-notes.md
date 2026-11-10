# SyncIO run loop and syncStep mirror, CE-0001 refutation (Phase 5, Lean side)

> Source: own work; Cats Effect source at v3.7.1 (`core/shared/src/main/scala/cats/effect/SyncIO.scala`, `IO.scala:1161-1162`, `IO.scala:2173-2178`, `IO.scala:2340-2402`, `kernel/.../Sync.scala:52-62`, `kernel/.../MonadCancel.scala:593-611`, `laws/.../AsyncLaws.scala:84-88`, `tests/shared/src/test/scala/cats/effect/IOSuite.scala:2577-2700`); cats-core 2.13.0 sources (`cats/Monad.scala:34-35`, `cats/ApplicativeError.scala:105`); scala-cli runs of `reproducers/CE-0001`
> Collected: 2026-11-10
> Published: 2026-11-10 (own research note)

## Files

- `CatsEffectInLean/Model/SyncIO.lean`: `SVal`, `SyncIO` (11 constructors, tag order), `SFn`/`SMap` closures, `SyncIO.runLoop` (structural on fuel), `succeeded`/`failed` (mutual, structural on `conts`; `mapK`, `flatMapK`, `handleErrorWithK` inlined). The run loop takes a `SyncIOEnv` (closure meaning) as a parameter.
- `CatsEffectInLean/Model/SyncStep.lean`: `SyncStep.interpret` (structural on fuel), `applyMap`, `callS`, `syncStep`, `steppedRest`; observations `SyncStepObs.directObs`, `SyncStepObs.steppedObs`.
- `CatsEffectInLean/Model/SyncStepExamples.lean`: 11 checks (IOSuite syncStep tests and single branches).
- `CatsEffectInLean/Props/Calibration/SyncStep.lean`: `syncStepIdentitySyncIO`.
- `CatsEffectInLean/Proofs/Calibration/SyncStep.lean`: `syncStepIdentitySyncIO_refuted`.

## Facts found

1. `SyncIOSync` does not override `map`. `G.map(fa)(f)` is `Monad.map` = `flatMap(fa)(a => pure(f(a)))` (cats-core 2.13.0 `Monad.scala:34-35`). So `interpret` builds `FlatMap` + `Pure` nodes, never `SyncIO.Map`. `.handleError(f)` is `handleErrorWith(f andThen pure)` (`ApplicativeError.scala:105`).
2. `G.defer(t)` = `flatMap(delay(t))(x => x)` (`Sync.scala:61-62`). The thunk returns a `SyncIO`, so the value universe needs `SyncIO` values (`SVal.sio`) and `IO` values (`SVal.io`).
3. `interpret` runs eagerly when `syncStep` is called. In the `Uncancelable` branch it calls the user body at once, without `try`. A throw there leaves `IO#syncStep` itself. Inside a `SyncIO` closure (`flatMap` continuation), `SyncIO` catches a non-fatal throw.
4. SyncIO's `AttemptK` increments `depth` (`SyncIO.scala:317`, `:343`); IOFiber's does not.
5. The root cancel scope of `SyncIO` is `Uncancelable` (`MonadCancel.Uncancelable`, `MonadCancel.scala:599`). So the two buggy branches (`IO.scala:2390-2397`) always fire for `IO#syncStep`. The law suite uses `G = F = IO` (scope `Cancelable`) and never reaches them.
6. A second witness that needs no external cancel: `IO.uncancelable(_ => IO.canceled *> flag.set(true))`. Direct: `canceled` is a no-op under the mask, result `Succeeded(())`, flag true. Stepped: the rest is `IO.canceled.flatMap(_ => ...)` without mask, result `Canceled`, flag false. Added as case 4 of the reproducer. Output on v3.7.1, `series/3.x` (`3.7.1-89-de84c01`) and `series/3.7.x` (`3.7.1-15-2f94201`): `canceled inside uncancelable is a no-op: direct=true stepped=false DIFFERENT`, `cases that differ: 4 / 4`, `REPRODUCED CE-0001`.

## Design decisions

- Stepped program = `fa.syncStep(limit).unsafeRunSync()` on the caller thread, then the law's selector, then a root fiber on the resulting heap. This is the pattern of `IOSuite.scala:2685`. The reproducer uses `.to[IO]` in a fiber instead; for case 4 both give the same rest.
- `IdPoll` is passed to user code as `Val.poll 0 0`. Real `poll` ids start at 1 in both mask models.
- Property semantics: the single-fiber driver (`Solo`, `List SoloChoice`), observation (summary, `Ref` cells, emitted values). Out of fuel and model aborts are "no claim". The shared `Eqv` (`Model/Enum.lean`) was not in this worktree.
- Why `Solo` and not the multi-fiber `Sched`: the refutation needs "no stepped run gives the direct observation" for all schedules. In `Solo`, the stepped run reaches only 10 states (closed under all choices; `cancel c` does not read `c` when no fiber is suspended). In `Sched`, each `cancel` choice adds a canceller fiber, so the reachable set is infinite.
- Why case 4 and not case 3 (`onCancel`): case 3 needs a suspended fiber and an external cancel. The canceller id `c` then enters the state, and the closure argument does not work without more lemmas. Case 2 needs `Sleep` (another agent adds it).

## Proof notes

- `rfl` proves `steppedRest (m + 6) ... = .ok (rest, heap)` with a free `m`: the kernel unfolds `m + 6` as `succ` six times.
- `Except` has no `DecidableEq` instance in Lean v4.35.0 core. Check a `Bool` predicate with `decide +kernel`, then recover the equation by `match`.
- Inductives that are not recursive inside a `mutual` block make `deriving DecidableEq` warn "unused termination_by". Move them out of the block.
- A higher-order helper that takes the recursive function (`andThen runLoop`) breaks structural recursion. Use a local `let go := fun ...` that calls `runLoop` directly.
