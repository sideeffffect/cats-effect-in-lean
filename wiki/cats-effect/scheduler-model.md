# Scheduler model (multi-fiber, replay)

> Sources: typelevel/cats-effect source at v3.7.1 (`IOFiber.scala`, `IO.scala`, `CallbackStack.scala`), read 2026-11-10; own difftest runner (`difftest/.../Runner.scala`, `Interp.scala`); own Phase 2 steps 6 and 8 (part) code in `CatsEffectInLean/Model/Step.lean`, `Sched.lean`, `SchedExamples.lean`; own replay runs on CE 3.7.1; `IODeferred.scala` and jvm-native `CallbackStack.scala` at v3.7.1; first `cediff` runs (2026-11-10); `RacePair`/`Sleep` mirror and runs (2026-11-10)
> Raw: [Scheduler model notes](../../raw/cats-effect/2026-11-10-scheduler-model-notes.md); [First difftest agreement notes](../../raw/project-decisions/2026-11-10-first-difftest-agreement-notes.md); [RacePair and Sleep notes](../../raw/cats-effect/2026-11-10-racepair-sleep-notes.md)

## Overview

Phase 2 steps 6 and 8. `Sched.lean` runs many fibers with the task order of the difftest replay mode. `Step.lean` now mirrors `IOCont`, `Get`, `Cede`, `Start`, `RacePair`, `Sleep`, the `IOCont` callback, and the runtime closures of `_cancel` and `_join`. `SchedExamples.lean` has 18 `decide +kernel` checks (about 1 s); `RaceSleepExamples.lean` has 4 more. Each check equals the Scala replay result of one difftest case (outcome, trace, steps, task order, pending). `lake check` accepts the library.

## Global state

- `Exec M` = focused fiber + `Heap` + fiber table `fibers`. `getFib`/`setFib` reach any fiber, so runtime closures and callbacks can change other fibers inside one step.
- `Heap` gains: `conts` (`ContState` cells), `ready` (`List Task`, enqueue order), `handles` (`CallbackStack` handles), `out` (user `emit`), `broken` (a broken invariant found inside `done` or a callback), `timers` (`Timer`: id, due time, `ContState`; creation order), `timerCount`. `clock` is in the `sleep` unit (ms in the difftest).
- `Task` = `fiber id` (one `IOFiber.run()`), `cb state result` (a callback task) or `timer id state` (a due timer, label `t<id>`).
- `Sched M`: heap, fiber table, the running `Loop` (or none), task count, schedule log, halt reason.

## Replay semantics (same as `Runner.replay`)

- One task = one `run()` until the run loop returns (end, `Get` suspension, `Cede`, auto-yield), or one callback task. Replay indices count tasks, so they align with Scala.
- `RChoice.pick n`: run ready task `n mod size`. No choices left: index 0 (FIFO).
- `RChoice.cancel t`: new fiber running `fiber(t).cancel`, run at once as one task. `t` is a model fiber id (Scala uses handles; root = 0 in both).
- Stop between tasks: root outcome (`Summary.done`), no ready task and no timer (`Summary.blocked`), task limit (`Summary.taskLimit` = Scala `fuel`). Model fuel counts micro-steps; `outOfFuel` is no claim.
- Time: when nothing is ready but timers exist, `Sched.advance` moves the clock to the earliest due time and appends all timers due then, in creation order (`LogEntry.advance`). It is its own micro-step: no task, no choice used. Scala does the same in the loop turn of the next pick; nothing runs between, so the order is the same.
- Enqueue points mirror `ec.execute`: root start, `Start` child (before the parent goes on), `RacePair` A then B (`FIB:937-938`), `Cede`, auto-yield, callback resume (`FIB:693`), `_cancel` takeover (`FIB:160`), `deferCb`, due timers.

## Mirrored concurrency code

- `_cancel` (`FIB:142-175`): `RtFn.cancel`, then `cancelAsync`, `cancelAsyncUnc`, `cancelAsyncK`, `getK` for the `IO.async_` takeover; `join.void` otherwise.
- `_join` (`FIB:179-195`, `IO.asyncCheckAttempt`): `RtFn.join`, `joinUnc`, `joinReg`, `joinSel`, `joinClear`.
- `fib.join`/`fib.cancel` read `_join`/`_cancel` when the term is built. User code sees `View.outcomes`; `IO.joinOf`/`IO.cancelOf` build the term.
- `done` calls callbacks in `CallbackStack.apply` order (constructor callback first, then newest first). A join callback runs `contCallback`.
- `contCallback` mirrors the three-way race: callback first (store), `Get` first (store and resume), second call (no-op), callback after cancel (loses `resume()`, stops). The spin of `loop()` is `Abort.cbSpin`.
- `Get` pushes `contGetFin` and (stack tracing on) `monitorDeregister`, each with `OnCancelK`.
- `IODeferred` (Phase 2 step 9, part): `get` reads `cell` when the term is built (`IO.deferredGetOf`, `View.deferreds`); `initial` is `IO.defer` + `asyncCheckAttempt` (same shape as `_join`); `complete` calls the waiters newest first and clears the stack. Cells: `Heap.deferreds`; allocation: `UserEffect.allocDeferred`. `pack` is not mirrored (no observable effect).
- `RacePair` (`FIB:908-952`): `IOCont(racePairBody)` = `IO.async` (`IO.scala:1418-1431`). The thunk `racePairRegister` makes A and B with race callbacks in the constructor slot (`raceLeft`/`raceRight`, `FIB:934-935`), enqueues A then B, and returns `Some` as a marker; `racePairSel` builds `onCancel(poll(get), cancel)`. `cancel` = `fiberA.cancel.start`, then `fiberB.cancel.start`, `cancelA.join`, `cancelB.join` (`RtFn.racePairCancelB`, `racePairJoinA`, `racePairJoinB`); only `fiberA.cancel` is read in the thunk.
- `Sleep` (`FIB:954-981`): `d > 0`: `IOCont(sleepBody d)`; the thunk adds a timer due at `clock + d` (`scheduler.sleep`, the difftest scheduler is not a `WorkStealingThreadPool`); the finalizer `IO(cancel.run())` removes it (`sleepCancel`). `d = 0`: `Cede`. A due timer task calls the `ContState` callback with `Right(())`.
- Not mirrored: foreign `EvalOn`, `Blocking` (`unsupportedTag`).

## Additive model changes (decision 13)

- `UserEffect.emit v` (trace output), `UserEffect.allocRef v` (new `Ref`), `UserEffect.allocDeferred` (new `IODeferred`).
- `UserEnv.callV` with a `View` (refs, fiber outcomes, `Deferred` cells); default calls `call`, so old environments still work.
- `OutcomeCb.ext` for fibers that the harness starts (external canceller).
- `Fn.user` has no captured values yet. The examples pack captured values into the id.

## Scala vs Lean (replay, all agree)

| Case | Outcome | Tasks |
|---|---|---|
| two-fibers-fifo / -chosen | Succeeded(VSucceeded(4)) | f0 f1 f2 f1 f2 f0 / f0 f2 f1 f1 f2 f0 |
| start-join | Succeeded(VSucceeded(5)) | f0 f1 f0 |
| cancel-child-oncancel | Succeeded(VCanceled) | f0 f1 f0 f1 f0 |
| cancel-child-masked / -end | Succeeded(VCanceled) / Succeeded(VSucceeded(1)) | f0 f1 f0 f1 f0 |
| async-later-twice | Succeeded(1) | f0 cb cb f0 |
| async-sync-once, async-later-error-first | Succeeded(1), Succeeded(Right(1)) | f0 |
| async-later-cancel | Canceled | f0 x0 cb f0 |
| async-no-cb-external-cancel, external-cancel-root | Canceled | f0 x0 f0 |
| external-cancel-root-before-start | Canceled | x0 f0 |
| never-blocked / fuel | blocked / fuel | f0 / f0 f0 f0 |

Traces and pending counts agree too (details in the raw note). These Lean terms are written by hand. `cediff` now runs generated cases on this scheduler: 161,811 replay cases agree on all fields, with no model fix needed ([Differential testing](../methodology/differential-testing.md), "Lean vs Scala results").

`RaceSleepExamples.lean` (cases of `difftest/cases/racesleep.jsonl`; schedule includes time advances, pending includes timers):

| Case | Outcome | Schedule | Pending, time |
|---|---|---|---|
| sleep-order | Succeeded(()) | f0 f1 f2 f3 [10: t2 t3] t2 t3 f2 f3 [20: t1] t1 f1 [30: t0] t0 f0 | 0, 30 |
| sleep-external-cancel | Canceled | f0 x0 f0 | 1, 0 |
| race-sleep | Succeeded(Right(fiber 1, Succeeded(()))) | f0 f1 f2 [5: t1] t1 f2 f0 | 1, 5 |
| race-loser-cancel | Succeeded(VCanceled) | f0 f1 f2 f0 f2 f0 | 0, 0 |

With `RacePair` and `Sleep`, every replay op of format v0 runs: 150,000 generated replay cases agree, 0 unsupported, no model bug ([RacePair and Sleep notes](../../raw/cats-effect/2026-11-10-racepair-sleep-notes.md)).

## Surprises

1. A canceled fiber whose `uncancelable` region is the last thing it does completes `Succeeded` (`cancel-child-masked-end`): no cancelation check between `UncancelableK` and `RunTerminusK`. Docs not checked yet.
2. `join b` after `b` completed is `IO.pure(oc)`, not an `IOCont`: the term depends on build time.
3. After an external cancel of the root, the canceller is resumed but never runs (the runner stops on the root outcome): `pending = 1`.
4. A `racePair` loser that fails is never reported to `reportFailure`, but an unjoined `start` fiber that fails is (`race-loser-error-lost` vs `start-error-reported`). The race callback in the constructor slot counts as a listener (`FIB:934-935`, `FIB:1099-1104`). Not triaged yet.
5. `racePair` does not cancel the loser; `IO.sleep(0)` is `IO.cede` (a yield, not a no-op); canceling a race starts two more canceller fibers.

## Open points

- Done: `tools/Difftest` runs on the scheduler (`Replay.lean`: handle-to-id map, task labels, `emit` trace, `allocRef`/`allocDeferred`).
- Done: `RacePair`, `Sleep` and timers. Open: foreign `EvalOn`, `Blocking`.
- Done: the order of `complete` with 2+ waiters (`difftest/cases/deferred.jsonl`: newest first; kills the planted reversal). Two timers with one due time: only in `racesleep.jsonl` (`sleep-order`), not in generated cases.
- Refinement mode (`observe = false`, cancel at any iteration).

## See Also

- [Run-loop model (single fiber)](runloop-model.md)
- [IO ADT and fiber state](io-adt-and-fiber-state.md)
- [TestControl and schedule replay](testcontrol.md)
- [Difftest program format](../methodology/difftest-program-format.md)
- [Fairness and liveness](../semantics/fairness-and-liveness.md)
- [Kernel evaluation of the model](../lean/kernel-evaluation.md)
