# TestControl / TestContext spike notes (Phase 0 step 2)

> Source: typelevel/cats-effect source at v3.7.1 (local checkout ~/Projects/cats-effect, commit eb0cc258fc732fc37f22f117c2e81d5554d67024); own experiment `spikes/testcontrol/ScheduleSpike.scala`
> Collected: 2026-11-10
> Published: 2026-08-23

Own notes. Citations are `<path>:<line>` at tag v3.7.1.
Paths: `TC` = `kernel-testkit/shared/src/main/scala/cats/effect/kernel/testkit/TestContext.scala`, `TCtl` = `testkit/shared/src/main/scala/cats/effect/testkit/TestControl.scala`, `FIB` = `core/shared/src/main/scala/cats/effect/IOFiber.scala`, `IO` = `core/shared/src/main/scala/cats/effect/IO.scala`, `RT` = `core/shared/src/main/scala/cats/effect/unsafe/IORuntime.scala`.

## How TestContext picks the next task

- `TestContext` is an `ExecutionContext` with a `scala.util.Random(_seed)` (TC:62-65).
- `execute(runnable)` makes `Task(id, runnable, runsAt = now, rnd = random.nextLong())` and adds it to a sorted set (TC:69-77).
- `schedule(delay, runnable)` does the same with `runsAt = now + delay` and returns a cancel thunk that removes the task (TC:213-226, 251-254).
- The set order is `runsAt`, then `id + rnd` (TC:318-327). The random key is drawn **at enqueue time**, not at pick time.
- `tickOne()` takes the **first** task of the set if `runsAt <= now`, removes it, runs it, and reports `NonFatal` errors to `reportFailure` (TC:152-173).
- `tick()` loops `tickOne()` (TC:175-179). `tickAll()` loops `tick()` + `advance(nextInterval())` until the set is empty (TC:197-204).
- So the order is: random priority per task, fixed by the seed and by the order of `execute` calls. It is not FIFO. It is not a choice we can make.
- `TestContext(seed: String)` takes a base64 seed; the same program gives the same interleaving (TC:270-281). The scaladoc warns that this breaks if the task lists differ, e.g. a different auto-cede point.
- `TestContext.apply()` and `apply(seed)` are public (TC:266, 280). `state.tasks` is public (TC:87-102), so a driver that uses `TestContext` directly can log the head task before each `tickOne()`. It cannot pick a non-head task.

## How TestControl builds the runtime

- `TestControl.execute(program, config, seed)` makes a `TestContext`, then `IORuntime(ctx, ctx.deriveBlocking(), scheduler, () => (), config)` (TCtl:360-395).
- The `Scheduler.sleep` goes to `ctx.schedule` (TCtl:373-377). Clock functions read `ctx.now()` (TCtl:379-386).
- Blocking work goes to `ctx.deriveBlocking()`, the same task set (TC:238-244).
- The `TestContext` is a private constructor field of `TestControl` (TCtl:123-125). Only `seed` is public (TCtl:283). So `TestControl` itself gives no log and no choice.
- `tickOne` = "Executes a single pending fiber" (TCtl:181-186). `isDeadlocked` = no result and no tasks (TCtl:275-276).
- `executeEmbed` = `tickAll` then embed the outcome; no result → `NonTerminationException` (TCtl:416-428).

## Public hook for a custom scheduler

- `IORuntime.apply(compute, blocking, scheduler, shutdown, config)` is public (RT:142-148). Any `ExecutionContext` and any `Scheduler` are accepted.
- The root fiber is submitted with `runtime.compute.execute(fiber)` (IO:1124-1146).
- `IOFiber` is a `Runnable` (`run()` at FIB:113-136). It is `private[effect]` (FIB:68). From outside, identify it by class name `cats.effect.IOFiber` and `System.identityHashCode`.
- `scheduleFiber` and `rescheduleFiber` use the `WorkStealingThreadPool` fast path only if the EC is a WSTP. Otherwise they call `scheduleOnForeignEC` = `ec.execute(fiber)` (FIB:1333-1376). `TestContext` is also a foreign EC. So a custom EC uses **the same code path as TestControl**.
- `Sleep` with a non-WSTP scheduler calls `scheduler.sleep(delay, () => cb(RightUnit))` (FIB:954-981). The timer task is a closure, not a fiber. When it runs, the callback enqueues the fiber. `Sleep(0)` is `IO.cede` (FIB:979).

## What one task is (granularity)

One task = one `IOFiber.run()` call. `run()` dispatches on `resumeTag` (FIB:121-131): `execR`, `asyncContinueSuccessfulR`, `asyncContinueFailedR`, `asyncContinueCanceledR`, `asyncContinueCanceledWithFinalizerR`, `blockingR`, `cedeR`, `autoCedeR`. Then the run loop runs many IO steps until one of these:

- `IO.cede` (tag 16): `resumeTag = CedeR`; `rescheduleFiber` (FIB:886-888). Task ends.
- Auto-cede: `cancelationIterations` counts down each step; at 0 a read barrier, reset to `cancelationCheckThreshold`, and `nextAutoCede -= threshold`; when `<= 0`, `resumeTag = AutoCedeR`; `rescheduleFiber` (FIB:224-239). JVM defaults: 512 and 2 × 512 = 1024 (`core/jvm/src/main/scala/cats/effect/unsafe/IORuntimeConfigCompanionPlatform.scala:27-32`). Configurable through `IORuntimeConfig`.
- Async suspend (`IOCont`/`Get`, tags 14/15): the fiber suspends. The callback later calls `resume()` and `scheduleFiber(ec, this)` with an `AsyncContinue*` tag (FIB:644-693). The resumption is a **new task**, run in the task of whoever called the callback.
- `start` (tag 17): new `IOFiber` + `scheduleFiber(ec, child)`; the parent **continues in the same task** (FIB:890-906).
- `racePair` (tag 18): two fibers enqueued, A then B (FIB:937-938), inside an `IO.async` registration.
- `cancel` of a suspended, unmasked fiber: the canceller takes the run loop and enqueues the target with `AsyncContinueCanceledWithFinalizerR` (FIB:142-161).
- `blocking` / `evalOn`: `scheduleOnForeignEC` on the other EC (FIB:983-1002, 1076-1085).
- Fiber end: `done`, callbacks (e.g. `join` waiters) run in the same task and enqueue the waiters.

Consequence: on a single thread, `canceled = true` from another fiber can only be set **between** tasks. Inside one task the fiber runs alone. Preemption inside a task, and a cancel seen in the middle of a task, happen only on a multi-thread runtime.

## Experiment

Script: `spikes/testcontrol/ScheduleSpike.scala` (Scala 3.3.4, cats-effect 3.7.1, cats-effect-testkit 3.7.1; scala-cli ran it on JVM 17).
Program: two fibers; each appends `x1` to a `Ref`, `IO.cede`, appends `x2`; parent joins both and reads the `Ref`.

- Part A: `TestControl.executeEmbed(program, seed = Some(s))`, 8 seeds, each run twice.
- Part B: `ScriptedEC` (an `ArrayBuffer` of ready runnables) + a virtual-time `Scheduler` in `IORuntime(ec, ec, scheduler, () => (), IORuntimeConfig())`. A driver loop removes `ready(choice)` and runs it. Choice list: index into the ready list; `-1` = newest; missing = 0 (FIFO). Each step logs the ready list and the pick.

Output (verbatim):

```
== Part A: TestControl, seeds ==
seed=MQ== -> List(b1, b2, a1, a2) (rerun equal: true)
seed=Mg== -> List(a1, a2, b1, b2) (rerun equal: true)
seed=Mw== -> List(b1, b2, a1, a2) (rerun equal: true)
seed=NA== -> List(b1, b2, a1, a2) (rerun equal: true)
seed=NQ== -> List(a1, a2, b1, b2) (rerun equal: true)
seed=Ng== -> List(a1, b1, a2, b2) (rerun equal: true)
seed=Nw== -> List(a1, a2, b1, b2) (rerun equal: true)
seed=OA== -> List(a1, a2, b1, b2) (rerun equal: true)
== Part B: scripted schedule ==
-- FIFO (all 0) -> outcome Some(Succeeded(List(a1, b1, a2, b2)))
   step 0: ready=[fiber#0] pick=0 -> fiber#0
   step 1: ready=[fiber#1,fiber#2] pick=0 -> fiber#1
   step 2: ready=[fiber#2,fiber#1] pick=0 -> fiber#2
   step 3: ready=[fiber#1,fiber#2] pick=0 -> fiber#1
   step 4: ready=[fiber#2,fiber#0] pick=0 -> fiber#2
   step 5: ready=[fiber#0] pick=0 -> fiber#0
-- chosen [0,1,0,1,...] -> outcome Some(Succeeded(List(b1, a1, a2, b2)))
   step 0: ready=[fiber#0] pick=0 -> fiber#0
   step 1: ready=[fiber#1,fiber#2] pick=1 -> fiber#2
   step 2: ready=[fiber#1,fiber#2] pick=0 -> fiber#1
   step 3: ready=[fiber#2,fiber#1] pick=1 -> fiber#1
   step 4: ready=[fiber#2,fiber#0] pick=0 -> fiber#2
   step 5: ready=[fiber#0] pick=0 -> fiber#0
-- chosen pick newest (LIFO) -> outcome Some(Succeeded(List(b1, b2, a1, a2)))
   step 0: ready=[fiber#0] pick=0 -> fiber#0
   step 1: ready=[fiber#1,fiber#2] pick=1 -> fiber#2
   step 2: ready=[fiber#1,fiber#2] pick=1 -> fiber#2
   step 3: ready=[fiber#1] pick=0 -> fiber#1
   step 4: ready=[fiber#1] pick=0 -> fiber#1
   step 5: ready=[fiber#0] pick=0 -> fiber#0
```

Observations:

- Seeds give 3 different outcomes over 8 seeds. Each seed is reproducible. The seed does not tell us the schedule.
- The scripted EC gives 3 different outcomes for 3 chosen schedules. Each step names the fiber. `fiber#0` is the root.
- Step 0 runs the root: it starts both children (enqueued, A then B) and suspends on `fa.join`. The root reappears in the ready list only after `fiber#1` (A) finishes (FIFO step 3 → step 4 list). This matches FIB:890-906 and the `join` callback path.
- 6 tasks for 3 fibers with 1 `cede` each: root (start, start, join-suspend), A part 1, B part 1, A part 2 (+ wake root), B part 2, root (join B, read, done).
