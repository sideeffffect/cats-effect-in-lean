# Dispatcher: structure, CE-0090, and mirror plan

> Sources: Cats Effect v3.7.1 (`std/shared/src/main/scala/cats/effect/std/Dispatcher.scala`, `Supervisor.scala`, `tests/shared/src/test/scala/cats/effect/std/DispatcherSuite.scala`); read-only `gh` searches; own scala-cli runs, 2026-11-25
> Raw: [Track P7D notes](../../raw/cats-effect/2026-11-25-track-p7d-dispatcher-notes.md)

## Overview

Phase 7 batch 7.2, track P7D. Status on 2026-11-25: one bug found and reproduced (CE-0090). No Lean mirror, no difftest ops, no registry entries yet (QUESTIONS.md Q6). Codec namespaces 90–99 and bug ids CE-0090+ are reserved for this track.

## Structure (v3.7.1)

- `impl(parallel, await, cancelable)` (:246-381) builds, in acquire order: outer `Supervisor(await, checkRestart = always)`, `terminationLatch` (Deferred), `doneR` (AtomicBoolean, `termination`), the executor, the workers, then supervises each `worker.run`.
- Release runs in reverse: worker `PoisonPill`s (:487) and each worker's inner `Supervisor(false)`; the executor (`parallel`: `Supervisor(await)`, joins or cancels tasks; `sequential`: nothing); `doneR.set(true)`; `terminationLatch.complete`; the outer Supervisor (joins or cancels the workers).
- Submission (`unsafeToFutureCancelable`, :288-372) is impure: check `doneR` (throw `IllegalStateException`), make `stateR = Unstarted(promisory)`, pick a worker (`parallel`: `ThreadLocalRandom.nextInt(Cpus)`), `unsafeOffer` a `Primary` registration. The cancel action negotiates `Unstarted → CancelRequested(latch)`, `Running(cancel) → Finalizer` registration, `Completed → Future.unit`.
- Worker loop (:411-470): `take` a registration; `Primary` with `Unstarted` runs the executor; `CancelRequested` completes the latch; `Finalizer` supervises the cancel; `PoisonPill` sets the worker `doneR`. After the pill the worker only waits for `terminationLatch` and never takes again.
- `UnsafeAsyncQueue.take` (:638-653) is a `cont` with a double-check on the latch callback.

## CE-0090: lost submission during release

The worker stops taking after the pill, but `doneR` is set only after the executor release. With `parallel(await = true)` the executor release waits for running tasks; a submission in that time passes the `doneR` check and is queued behind the pill. It never runs, its `Future` never completes, and its cancel action waits forever. `parallel(await = false)` has a short window (about 70 ms). `sequential` throws as promised. Reproduced on v3.7.1 and series/3.x: 50/50 TestControl seeds, 50/50 real runs ([bug record](../../bugs/CE-0090.yaml)).

The upstream test "reject new tasks while shutting down" (`DispatcherSuite.scala:500-517`) cannot fail: it ends with `yield fail("fail")`, so `r.isLeft` holds in every run.

Known, not bugs: a canceled dispatched effect never completes its `Future` (#2448); `sequential` cannot cancel queued or running work (#4069, comment :233-235).

## Mirror plan (not started)

1. Wait for track V's `Supervisor` mirror (both `checkRestart` paths, `applyForAsync`). An exact replay difftest needs the exact fiber structure of `Supervisor`.
2. Mirror the submission as one atomic step: a harness fiber runs the impure code in one `IO.delay` thunk (uncancelable, never canceled). This is how the Scala difftest calls it too. A split check/offer (two thunks) models the multi-thread race inside the submission.
3. Mirror `Promise`/`Future` as cells the harness reads without blocking (`future.value`). Do not use `IO.fromFuture` in the Scala runner: it is not cancelable.
4. Run the Scala difftest JVM with `-XX:ActiveProcessorCount=1` so that `Cpus = 1` and the worker choice is fixed; the model takes the worker choice as an input.
5. Properties to state: `noLostSubmission` (refuted by CE-0090; fixed twin: set `doneR` before the pills and drain the queue after the pill), at-most-once and exactly-once execution, sequential FIFO and one at a time, cancel-before-start prevents, cancel-after-start cancels and its Future completes, submit after release throws, release with `await` waits/cancels, no leaked fiber.

## See Also

- [Semaphore and Mutex model](semaphore-mutex-model.md)
- [CountDownLatch and CyclicBarrier model](latch-barrier-model.md)
- [Resource model](resource-model.md)
- [Bug history](bug-history.md)
- [Agent workflow](../methodology/agent-workflow.md)
