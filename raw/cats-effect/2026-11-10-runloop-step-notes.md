# IOFiber.runLoop single-fiber mirror: facts found while mirroring (research note)

> Source: https://github.com/typelevel/cats-effect/tree/v3.7.1 (local checkout ~/Projects/cats-effect at v3.7.1): `core/shared/src/main/scala/cats/effect/IOFiber.scala`, `core/jvm/src/main/java/cats/effect/IOFiberConstants.java`, `core/shared/src/main/scala/cats/effect/unsafe/IORuntimeConfig.scala`, `core/jvm/src/main/scala/cats/effect/unsafe/IORuntimeConfigCompanionPlatform.scala`, `core/jvm-native/src/main/scala/cats/effect/CallbackStack.scala`, `kernel-testkit/shared/src/main/scala/cats/effect/kernel/testkit/TestContext.scala`; own Lean model `CatsEffectInLean/Model/Step.lean`, `Run.lean`, `StepExamples.lean`; own scala-cli check (CE 3.7.1, TestControl.executeEmbed, Scala 3.3.4, JVM 17)
> Collected: 2026-11-10
> Published: 2026-08-23

Own notes, written for Phase 2 step 5 (single fiber). `FIB` = `core/shared/src/main/scala/cats/effect/IOFiber.scala` at v3.7.1.

## Run-loop structure

- One `runLoop` call = one iteration (`FIB:211-1073`). Order: `EndFiber` check (`FIB:220-222`); `nextCancelation = cancelationIterations - 1`; if `<= 0`: read barrier, reset to `cancelationCheckThreshold`, `nextAutoCede -= threshold`, and if `<= 0` auto-yield (`resumeTag = AutoCedeR`, `resumeIO = cur`, `rescheduleFiber`) (`FIB:224-240`); then `shouldFinalize()` (`FIB:242-244`); then the tag dispatch.
- The counters are only tested with `<= 0` and only decrease by subtraction until reset. So `Nat` truncated subtraction gives the same tests as Scala `Int`.
- Fast paths (`Map`/`FlatMap`/`Attempt` over `Pure`, `Error`, `Delay`, `RealTime`, `Monotonic`, `ReadEC`) pass `nextCancelation - 1`: they count as two iterations for the barrier and auto-yield counters (`FIB:339`, `FIB:347`, ...).
- `succeeded`/`failed` unwind several continuations inside ONE iteration. There is no cancelation check between continuations. Only `MapK` checks `depth > MaxStackDepth` (512, `IOFiberConstants.java:26`) and then returns `IO.Pure`/`IO.Error` to the run loop (`FIB:1226-1228`). `failed` has no depth check.
- Depth increments: `MapK`, `OnCancelK`, `UncancelableK`, `UnmaskK`, and a caught throw in `FlatMapK`/`HandleErrorWithK`: `+1`. `HandleErrorWithK` (success), `AttemptK`, and dropped `MapK`/`FlatMapK` in `failed`: same depth.
- Defaults: `cancelationCheckThreshold = 512`, `autoYieldThreshold = 2 * 512` (`IORuntimeConfigCompanionPlatform.scala:26-32`); `reportUnhandledFiberErrors = true` (`IORuntimeConfig.scala:178`).

## try/catch placement (which user code is inside `try`)

- In `try` with `UnsafeNonFatal` / `onFatalFailure`: `Delay` thunk (`FIB:279-286`), `Map`/`FlatMap` functions (`FIB:322-334`, `FIB:398-405`), `f(thunk())` in one `try` for the `Delay` fast paths (`FIB:359`, `FIB:429`), `Attempt` over `Delay` (`FIB:486-496`), `Uncancelable` body (`FIB:569-576`, a throw becomes `IO.raiseError(t)` and `UncancelableK` is still pushed), `IOCont` body (`FIB:760-767`), `MapK`/`FlatMapK`/`HandleErrorWithK` in `succeeded`/`failed`.
- NOT in `try`: `Local` (`FIB:1061`). A throw (fatal or not) leaves `runLoop` and `run()`. Under `TestControl` the `TestContext` catches non-fatal throws of a task and calls `reportFailure` (`TestContext.scala:161-162`). The fiber never completes.
- The `Error` branch also checks `UnsafeNonFatal`: `IO.raiseError(fatal)` calls `onFatalFailure` (`FIB:266-267`, `FIB:344-345`, `FIB:415-416`, `FIB:470-471`).

## Cancelation details

- `OnCancel` pushes `EvalOn(fin, currentCtx)`, not `fin` (`FIB:545`). On the same `ExecutionContext` the `EvalOn` fast path (`FIB:987-988`) runs it in place. So the mirror needs the `EvalOn` fast path even for one fiber.
- `prepareFiberForCancelation` resets `conts`/`objectState` and adds a mask only when `finalizing` is false (`FIB:1134-1146`). A second call during finalization only pops the next finalizer and keeps the current `conts`.
- `cancelationLoopFailureK` reports the finalizer error with `currentCtx.reportFailure` and goes on with the next finalizer (`FIB:1487-1490`).
- `execR` with `canceled = true` calls `done(Canceled)` without running anything (`FIB:1388-1389`).
- External `cancel` (`FIB:142-175`): `canceled = true` is a plain write; if `resume()` wins (the target is suspended) and it is unmasked, the canceller pushes its callback on `objectState` and schedules the target with `AsyncContinueCanceledWithFinalizerR`; if masked, it calls `suspend()` again and joins; if the target runs, it joins. `cancel` and `join` read barriers (`FIB:197-207`).
- `done` calls every callback (`CallbackStack.apply`, `CallbackStack.scala:61-85`). It reports an `Errored` outcome only if no callback was called (`FIB:1099-1104`).

## Observed behaviour (model prediction, then checked on real CE 3.7.1 with TestControl.executeEmbed)

| Program | Model (counter masks) | Real CE 3.7.1 |
|---|---|---|
| `IO.uncancelable(_ => IO.canceled >> IO.pure(1))` | Succeeded(1) | `Right(1)` |
| `IO.uncancelable(_ => IO.canceled).flatMap(_ => IO.pure(2))` | Canceled | `CancellationException` |
| `IO.uncancelable(_ => IO.canceled).map(_ => 2)` | Succeeded(2) | `Right(2)` |
| escaped poll: `uncancelable(p => pure(p)).flatMap(p => uncancelable(_ => p(canceled) >> pure(1)))` | Canceled (spec model: Succeeded(1)) | `CancellationException` |
| escaped poll in finalizer: `uncancelable(p => pure(p)).flatMap(p => canceled.onCancel(p(log 0)).onCancel(log 1))` | Canceled, log `[]` (spec model: log `[0, 1]`) | `CancellationException`, log `List()` |
| 512 maps of `_ + 1` after `uncancelable(_ => canceled >> pure(1))` | Succeeded(513) | `Right(513)` |
| 513 maps | Canceled | `CancellationException` |

Checker source (scala-cli, `//> using dep org.typelevel::cats-effect:3.7.1` and `cats-effect-testkit:3.7.1`): each program `io` is run as `TestControl.executeEmbed(io.attempt).attempt.unsafeRunSync()`; `log(k) = IO(ref.updateAndGet(k :: _))`.

## Oddities (candidates, not bug records)

1. `fa.map(f)` vs `fa.flatMap(a => IO.pure(f(a)))` differ in outcome after `uncancelable(_ => canceled)`: `map` unwinds to `RunTerminusK` in the same `succeeded` call; `flatMap` returns a new `IO` and the next iteration sees `canceled`. Probably intended ("cancelation is observed at boundaries"), but it breaks outcome-level map/flatMap coherence.
2. The depth-512 hand-back is an observable cancelation point: 512 vs 513 `map`s change the outcome.
3. An escaped `poll` used in a finalizer (counter model) unmasks the finalizer region, because `prepareFiberForCancelation` adds exactly one mask (`FIB:1145`), and the escaped `poll` id is 1. Then every remaining finalizer is popped one per iteration without running (`FIB:1133-1149` with `finalizing = true`). Finalizers are skipped: a resource-safety break, but it needs a `poll` that escaped its region. Docs status of escaped `poll` must be checked before any bug record.
4. `Local` has no `try`; a throwing `IOLocal` function makes the fiber hang.
