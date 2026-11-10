# Run-loop model (single fiber)

> Sources: typelevel/cats-effect source at v3.7.1 (`IOFiber.scala`, `IOFiberConstants.java`, `IORuntimeConfig.scala`, `CallbackStack.scala`, `TestContext.scala`), read 2026-11-10; own Phase 2 step 5 code in `CatsEffectInLean/Model/Step.lean`, `Run.lean`, `StepExamples.lean`; own scala-cli check on CE 3.7.1 with `TestControl.executeEmbed`
> Raw: [Run-loop step notes](../../raw/cats-effect/2026-11-10-runloop-step-notes.md)

## Overview

Phase 2 step 5 and the single-fiber part of steps 6 and 10. `step` mirrors one iteration of `IOFiber.runLoop` for one fiber. Both mask models work (`MaskModel M` parameter). User code comes from `UserEnv`. `StepExamples.lean` has 34 numbered examples (47 checks), all by `decide +kernel`. They build in about 4.5 s, including two 1,100-step runs. `lake check` accepts the library (axioms `propext`, `Classical.choice`, `Quot.sound`).

## Files and shape

- `Step.lean`: `Config` (thresholds 512/1024, `maxStackDepth` 512, `reportUnhandledFiberErrors`), `Heap` (refs, clock, runtime trace), `Exec` (fiber + heap), `Loop` (`runLoop` arguments + `pendingCancel`), `step`, `resume` (= `run()`), `cancelFiber`.
- `succeeded`/`failed` are mutually structural on the `conts` list (`termination_by structural`). Each Scala recursive call pops one byte first, so this is exact.
- `Run.lean`: `Solo` (running, parked, suspended, done, fatal, uncaught, aborted), `SoloChoice` (`step observe`, `cancel canceller`), `Solo.exec` structural on the schedule. A finished schedule with a runnable fiber is `Summary.outOfFuel`.

## Result types

- `Flow` (inside one iteration): `io cur` | `fatal e` (`onFatalFailure`) | `uncaught e` (throw out of `Local`) | `abort a`.
- `StepResult`: `continue loop` | `yielded` (auto-yield; the scheduler resumes with `autoCedeR`) | `suspended` (stub: `EndFiber` without outcome) | `done oc` | `fatal e` | `uncaught e` | `aborted a`.
- `Abort`: `unsupportedTag t` (tags 14–19, 21, foreign `EvalOn` 20), `unsupportedResume`, `unsupportedFn`, `unsupportedEffect` (user code calls an `IOCont` callback), `illTyped`, and three broken-invariant cases. Never a Cats Effect outcome.

## Mirrored branches

- `runLoop`: `EndFiber` check, cancelation counter and read barrier, auto-yield, `shouldFinalize`, then tags `Pure`, `Error` (fatal check), `Delay`, `RealTime`, `Monotonic`, `ReadEC`, `Map` and `FlatMap` (fast paths over `Pure`/`Error`/`Delay`/`RealTime`/`Monotonic`/`ReadEC`, counted as 2 iterations), `Attempt` (same fast paths), `HandleErrorWith`, `Canceled`, `OnCancel` (pushes `EvalOn(fin, ctx)`), `Uncancelable`, `UnmaskRunLoop`, `EvalOn` (same-context fast path only), `Local` (no `try`), `IOTrace`, `ReadRT`.
- `succeeded`/`failed`: all 10 continuation tags in source order (`EvalOnK` aborts: only reachable after a foreign `EvalOn`), the depth-512 hand-back in `MapK`.
- `done`, `prepareFiberForCancelation`, `cancelationLoopSuccessK`/`FailureK`, `runTerminusSuccessK`/`FailureK`.
- `run()` resume tags: `execR`, `asyncContinueSuccessfulR`/`FailedR`/`CanceledR`/`CanceledWithFinalizerR`, `cedeR`, `autoCedeR`, `doneR`; `blockingR` aborts.
- External `cancel` (local part): a running target gets `pendingCancel` (a plain write that is not yet visible); an off-loop target gets `canceled = true`; a suspended unmasked target is taken over (`AsyncContinueCanceledWithFinalizerR` + canceller callback on `objectState`). The canceller's own wait (`join`, `IO.async_`) needs the multi-fiber scheduler (step 8).

## Visibility of external cancel

`Loop.pendingCancel` models the plain `canceled` write of another thread. It becomes visible at the read barrier (every `cancelationCheckThreshold` iterations), at `run()`, or at a step with `observe = true`. With `observe = false` the fiber can finish first (example 30: `Succeeded`).

## Examples: results

All examples agree with the docs or the laws, except where noted. Both mask models give the same result unless noted.

| Program | Result |
|---|---|
| `uncancelable(_ => canceled >> pure 1)` | Succeeded(1) |
| `uncancelable(_ => canceled).flatMap(_ => pure 2)` | Canceled |
| `uncancelable(_ => canceled).map(f)` | Succeeded, `f` ran |
| `uncancelable(poll => poll(canceled))` | Canceled |
| `onCancel` finalizers | LIFO; an error in a finalizer is reported, the next one runs |
| `handleErrorWith` / `attempt` of `canceled` | Canceled (not caught) |
| nested regions, outer `poll` inside inner region | no-op (outer block wins) |
| escaped `poll` in a new region | counter: Canceled; spec: Succeeded(1) |
| escaped `poll` in a finalizer | counter: Canceled, NO finalizer body runs; spec: both run |
| cancel before first run | Canceled, nothing runs (`execR`) |
| 512 / 513 maps after `uncancelable(_ => canceled >> pure 1)` | Succeeded(513) / Canceled |

The rows with real CE claims (`map` vs `flatMap`, escaped `poll`, 512/513) were checked on CE 3.7.1 with `TestControl.executeEmbed`. All agree with the counter model. So for the escaped `poll`, `IOFiber` = counter model, and the spec model is the one that differs.

## Surprises

1. `map` after `uncancelable(_ => canceled)` is not a cancelation boundary, but `flatMap` is. `fa.map(f)` and `fa.flatMap(a => pure(f(a)))` give different outcomes. Twin to difftest; probably intended.
2. The depth-512 hand-back in `succeeded` is an observable cancelation point (512 vs 513 maps).
3. An escaped `poll` used in a finalizer makes CE skip all remaining finalizers (`prepareFiberForCancelation` with `finalizing = true` only pops). Real on 3.7.1. Needs a `poll` that escaped its region; check the docs before a bug record.
4. `OnCancel` stores `EvalOn(fin, ctx)`, so the `EvalOn` fast path is part of every finalizer run.
5. `IO.raiseError(fatal)` is fatal: the `Error` branch calls `onFatalFailure`.

## Open points

- Step 8 (rest): `RacePair`, `Sleep`, foreign `EvalOn`, `Blocking`. `IOCont`/`Get`, `Cede`, `Start` and the canceller side of `cancel` are done: see [Scheduler model](scheduler-model.md). Since then `Cede` works in the single-fiber driver too (example 16), and user callback effects run (`Abort.unsupportedEffect` is unused).

## See Also

- [IO ADT and fiber state](io-adt-and-fiber-state.md)
- [SyncIO and syncStep model](syncio-and-syncstep-model.md)
- [Scheduler model (multi-fiber, replay)](scheduler-model.md)
- [Semantics of CE3](semantics.md)
- [Fairness and liveness](../semantics/fairness-and-liveness.md)
- [Kernel evaluation of the model](../lean/kernel-evaluation.md)
- [TestControl and schedule replay](testcontrol.md)
- [Project plan](../methodology/project-plan.md)
