# TestControl, TestContext and schedule replay

> Sources: cats-effect v3.7.1 source (`TestContext.scala`, `TestControl.scala`, `IOFiber.scala`, `IO.scala`, `IORuntime.scala`); own experiment `spikes/testcontrol/ScheduleSpike.scala`, run 2026-11-10
> Raw: [TestControl spike notes](../../raw/cats-effect/2026-11-10-testcontrol-spike-notes.md); [Test runtime docs](../../raw/cats-effect/cats-effect-docs-test-runtime.md)

## Overview

Phase 0 step 2 answer. `TestControl` runs real `IO` on one thread with virtual time. Its task order is random per seed. We cannot choose the order and cannot read it.
A custom `ExecutionContext` in a public `IORuntime(...)` can do both. It uses the same IOFiber code path as `TestControl`. The experiment confirms this.
Decision: the difftest uses **schedule replay** (primary) and **refinement** (secondary). Confidence 0.85.
Citation keys (`TC`, `TCtl`, `FIB`, `IO`, `RT`) are defined in the raw note.

## (a) How TestContext picks the next task

- Each `execute` / `schedule` call makes a `Task(id, runnable, runsAt, rnd)`. `rnd = random.nextLong()` from the seed (TC:69-77, 213-226).
- Tasks sit in a sorted set ordered by `runsAt`, then `id + rnd` (TC:318-327). The random priority is fixed **at enqueue time**.
- `tickOne()` runs the head task if it is due (TC:152-173). `tick` loops it. `tickAll` also advances time to the next timer (TC:197-204).
- So: not FIFO, not a free choice. A seed reproduces a run only if the task lists are the same (TC:270-281).
- `TestControl` hides its `TestContext` (TCtl:123-125). Only `seed` is public (TCtl:283).
- Using `TestContext` directly, a driver can read `state.tasks` (TC:87-102). It can log the next task. It cannot pick another task.

**Smallest mechanism for a Lean-chosen schedule:** a ~20-line `ExecutionContext` that keeps ready runnables in a list, plus a virtual-time `Scheduler`. Pass both to the public `IORuntime(compute, blocking, scheduler, shutdown, config)` (RT:142-148). A driver loop removes `ready(choice_i)` and calls `run()`.

- `IOFiber.scheduleFiber`/`rescheduleFiber` take the WSTP fast path only for a `WorkStealingThreadPool`. Any other EC gets `ec.execute(fiber)` (FIB:1333-1376). `TestContext` is such an EC too. So the custom EC exercises the same fiber code as `TestControl`.
- The root fiber enters through `runtime.compute.execute(fiber)` (IO:1146).

## (b) Logging which task ran

- Yes, with the custom EC. The runnable **is** the `IOFiber` (FIB:113). Identify it by class name `cats.effect.IOFiber` (the class is `private[effect]`, FIB:68) and `System.identityHashCode`.
- Fiber labels in order of first enqueue equal creation order, because `start` and `racePair` enqueue a fiber when they create it (FIB:904, 937-938).
- Timer tasks are closures, not fibers (`scheduler.sleep(delay, () => cb(RightUnit))`, FIB:972). Log them as timer tasks.
- Reflection on the private `resumeTag` field could also log why the fiber resumed (cede, auto-cede, async continue, cancel). Not done yet.

## (c) Task granularity vs run-loop steps

One task = one `IOFiber.run()` (FIB:113-136). It runs many run-loop steps. It ends when the fiber:

- cedes (`IO.cede`, tag 16, FIB:886-888), or `sleep(0)` which is `cede` (FIB:979);
- auto-cedes after `autoYieldThreshold` steps (default 1024 = 2 × 512 on JVM), checked at each `cancelationCheckThreshold` boundary (FIB:224-239);
- suspends in `async`/`IOCont` (FIB:604-769); the callback later enqueues the fiber as a **new** task with an `AsyncContinue*` tag (FIB:676-693);
- moves to another EC (`blocking`, `evalOn`; FIB:983-1002, 1076-1085);
- finishes; `join` waiters are woken inside the same task.

`start` enqueues the child and the **parent keeps running** in the same task (FIB:890-906).
On one thread, another fiber's `cancel` sets `canceled` only **between** tasks. Mid-task preemption and mid-task cancel observation exist only on the multi-thread runtime.
Model consequence: the Lean scheduler must expose task-level choice points (the ready list, in enqueue order) for replay. Its finer choice points (cancel at any step) stay for the refinement mode.

## (d) Difftest mode: both, replay first

1. **Schedule replay (primary, deterministic).** The generator (or Lean) emits a choice list. Scala runs it on the scripted EC and logs `(step, ready list, picked fiber)`. Lean runs the same list and must give the same outcome, trace and ready lists. Checking is a total function. A mismatch points to the first diverging step. This needs the Lean model to keep the ready queue in the same enqueue order as `IOFiber` (e.g. `racePair` enqueues A then B).
2. **Refinement (secondary).** For `TestControl` with seeds and for the real `IORuntime` (WSTP, many threads): the observed outcome must be in the Lean outcome set over all schedules. This catches races that the single thread hides, and checks that our EC does not differ from `TestControl`.

Reasons: replay removes nondeterminism, so 50,000 cases give a sharp signal (Netsem lesson). Refinement alone accepts a too-loose model. Replay alone never sees multi-thread behavior.

## Experiment result (2026-11-10)

Program: two fibers, each `append x1; cede; append x2`, parent joins both. Full output in the raw note.

- `TestControl`, 8 seeds: 3 different outcomes (`b1,b2,a1,a2`, `a1,a2,b1,b2`, `a1,b1,a2,b2`). Each seed reproduces.
- Scripted EC: FIFO → `a1,b1,a2,b2`; choices `[0,1,0,1,…]` → `b1,a1,a2,b2`; newest-first → `b1,b2,a1,a2`. Six logged steps each, with fiber ids.
- Script: `spikes/testcontrol/ScheduleSpike.scala` (`scala-cli run`).

## Open points

- Does the generator emit choice lists, or does Lean pick them? Either works; choice lists are data in the JSON case.
- Cancel from outside the program (harness-driven) needs a step in the choice list. Not tested yet.
- `IORuntime.apply` registers the runtime in a global set and a fiber monitor (RT:112-140). Harmless for tests; call `shutdown` per case if memory grows.

## See Also

- [Differential testing](../methodology/differential-testing.md)
- [Source layout](source-layout.md)
- [Semantics of CE3](semantics.md)
- [Project plan](../methodology/project-plan.md)
- [Modeling approaches](../semantics/modeling-approaches.md)
