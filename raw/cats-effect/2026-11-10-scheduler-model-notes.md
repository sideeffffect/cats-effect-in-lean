# Multi-fiber scheduler model: facts found while mirroring (research note)

> Source: https://github.com/typelevel/cats-effect/tree/v3.7.1 (local checkout ~/Projects/cats-effect at v3.7.1): `core/shared/src/main/scala/cats/effect/IOFiber.scala`, `core/shared/src/main/scala/cats/effect/IO.scala`, `core/jvm-native/src/main/scala/cats/effect/CallbackStack.scala`; own difftest runner `difftest/src/main/scala/cats/effect/difftest/Runner.scala` and `Interp.scala`; own Lean model `CatsEffectInLean/Model/Step.lean`, `Sched.lean`, `SchedExamples.lean`; own replay runs of `difftest/cases/basic.jsonl` and `difftest/cases/sched.jsonl` on CE 3.7.1
> Collected: 2026-11-10
> Published: 2026-08-23

Own notes, written for Phase 2 steps 6 and 8 (part). `FIB` = `core/shared/src/main/scala/cats/effect/IOFiber.scala` at v3.7.1.

## Ready list order (scripted EC)

- `scheduleFiber` and `rescheduleFiber` both end in `ec.execute(fiber)` when the EC is not a `WorkStealingThreadPool` (`FIB:1333-1376`). So under the difftest `ScriptedEC`, `Cede` and auto-yield also append to the end of the ready list. There is no "local queue" order difference.
- Enqueue points: root `unsafeRunFiber` (`IO.scala:1146`); `Start` enqueues the child, then the parent continues in the same task (`FIB:904-906`); `Cede` (`FIB:887-888`); auto-yield (`FIB:234-237`); the `IOCont` callback on a waiting fiber (`FIB:693`); the `_cancel` takeover (`FIB:160`); user `ec.execute(task)` (difftest `later` callbacks).
- A difftest external cancel makes a new fiber with `f.cancel.unsafeRunFiber`; the runner removes it from the ready list and runs it at once. Net effect on the ready list: none, except what the canceller itself enqueues.

## `_cancel` and `_join` are read when the term is built

- `fiber.cancel` = `readBarrier(); _cancel` and `fiber.join` = `readBarrier(); _join` (`FIB:197-207`). `done` swaps them for `IO.unit` and `IO.pure(oc)` (`FIB:1094-1095`). The term depends on the time of the read, not the time of the run.
- Example: in `two-fibers-fifo`, `join a` is built in task 1 (an `IOCont`, the root suspends), and `join b` is built in task 6 after `b` completed (`IO.pure(oc)`, no `IOCont`).
- Lean: `View.outcomes` lets user code see fiber outcomes; `IO.joinOf`/`IO.cancelOf` build the two terms.

## `_cancel` body (FIB:142-175)

- `canceled = true`, then `resume()` (`suspended.getAndSet(false)`).
- Suspended and unmasked: `IO.async_ { fin => resumeTag = AsyncContinueCanceledWithFinalizerR; objectState.push(fin); scheduleFiber(currentCtx, this) }`. The canceller suspends in `Get` until the target's cancelation loop calls `fin(Right(()))` (`FIB:1155`, `FIB:1476`).
- Suspended and masked: `suspend()` again, then `join.void`.
- Not suspended (running or in the ready list): `join.void`.
- The whole body is inside `IO.uncancelable { _ => ... }`, so the canceller's wait is masked.

## `_join` (FIB:179-195, `IO.asyncCheckAttempt`, `IO.scala:1353-1368`)

- Body: `G.uncancelable { poll => lift(k(resume)).flatMap { Right(a) => pure(a); Left(Some(fin)) => onCancel(poll(get), fin); Left(None) => get } }`.
- `k` pushes `oc => cb(Right(oc))` on the target's `CallbackStack` and returns `Left(Some(IO { clearHandle }))`, or `Right(outcome)` if done.
- `CallbackStack.apply` calls the constructor callback first, then the pushed nodes from the head (newest first). The Lean model keeps handle 0 for the constructor callback.

## `IOCont` callback (FIB:644-755)

- `stateLoop`: "initial" → store result, stop (callback first). "waiting" → store result, then `loop()`. "result" → no-op (second call ignored).
- `loop()`: if `resume()` wins and `finalizing == state.wasFinalizing`: push result and `AsyncContinueSuccessfulR`/`FailedR`, or `AsyncContinueCanceledR` if `shouldFinalize()`; then `scheduleFiber`. If `resume()` loses: spin only while not canceled, not completed and same finalizing state. With one thread the spin cannot end; the Lean model marks it `Abort.cbSpin`. No replay case reaches it.
- Callback after cancel (`async-later-cancel`): the canceller took the run loop first, so `resume()` loses; the target is canceled and unmasked, so the callback stops. Only the target's finalizers run.

## `Get` (FIB:771-883)

- Always pushes `fin = IO { state.compareAndSet(waiting, null) }` and `OnCancelK`. With stack tracing (default, `cached`) it also pushes `IO { handle.deregister() }` and a second `OnCancelK` before suspension.
- After `suspended.getAndSet(true)`, it checks `shouldFinalize()` again (race with cancel). One thread: if the fiber is canceled and unmasked here, it runs the finalizers at once.
- "waiting" in the else branch is called impossible in a comment; Scala would throw `MatchError`. Lean: `Abort.badContState`.

## Lean vs Scala comparison (replay mode, all agree)

| Case | Scala outcome | Steps | Tasks | Lean |
|---|---|---|---|---|
| two-fibers-fifo | Succeeded(VSucceeded(4)) | 6 | f0 f1 f2 f1 f2 f0 | same, trace 1 3 2 4 |
| two-fibers-chosen [0,1,0,1,...] | Succeeded(VSucceeded(4)) | 6 | f0 f2 f1 f1 f2 f0 | same, trace 3 1 2 4 |
| start-join | Succeeded(VSucceeded(5)) | 3 | f0 f1 f0 | same |
| cancel-child-oncancel | Succeeded(VCanceled) | 5 | f0 f1 f0 f1 f0 | same, fin then call(1,9) |
| cancel-child-masked | Succeeded(VCanceled) | 5 | f0 f1 f0 f1 f0 | same, call(0,1) only |
| cancel-child-masked-end | Succeeded(VSucceeded(1)) | 5 | f0 f1 f0 f1 f0 | same |
| async-later-twice | Succeeded(1) | 4 | f0 cb0.0 cb0.1 f0 | same |
| async-sync-once | Succeeded(1) | 1 | f0 | same |
| async-later-error-first | Succeeded(Right(1)) | 1, 1 pending | f0 | same |
| async-later-cancel [0, cancel 0] | Canceled | 4, 1 pending | f0 x0 cb0.0 f0 | same |
| async-no-cb-external-cancel | Canceled | 3, 1 pending | f0 x0 f0 | same |
| external-cancel-root | Canceled | 3, 1 pending | f0 x0 f0 | same |
| external-cancel-root-before-start | Canceled | 2, 1 pending | x0 f0 | same |
| never-blocked | blocked | 1 | f0 | same |
| fuel (maxSteps 3) | fuel | 3, 1 pending | f0 f0 f0 | same (`taskLimit`) |

The Lean side is hand-written terms (`SchedExamples.lean`), not the automatic translation. The "pending 1" after a root cancel is the canceller fiber: the root's cancelation loop resumed it, but the runner stops before it runs.

## Observations

- `cancel-child-masked-end` (checked on CE 3.7.1 and in Lean): if nothing follows the `uncancelable` region in the child, the child completes `Succeeded(1)` although `cancel` set `canceled = true`: `succeeded` unwinds `UncancelableK` and `RunTerminusK` in one iteration, with no cancelation check between. `cancel-child-masked` adds a `delay` after the region, and then the child is `Canceled`. Not checked against the docs yet. Before any bug record, look for a doc sentence that promises `Canceled` here.
- Kernel cost: the 18 `decide +kernel` checks in `SchedExamples.lean` build in about 1 s.
