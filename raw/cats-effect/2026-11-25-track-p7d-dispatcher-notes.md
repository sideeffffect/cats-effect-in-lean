# Track P7D (Dispatcher) notes, 2026-11-25

Source: own reading of `std/shared/src/main/scala/cats/effect/std/Dispatcher.scala` and
`Supervisor.scala` at v3.7.1; scala-cli runs; read-only `gh` searches. Do not edit.

## Resource order of `Dispatcher.impl` (Dispatcher.scala:246-381)

Acquire order: outer `Supervisor(await, checkRestart = always)` (:254), `awaitTermination`
(Deferred, :260), `termination` (AtomicBoolean `doneR`, :257), executor (:263-269), workers
(:274-279; each `Worker.apply` = `Supervisor(false)` then `Resource.make(new Worker)(offer
PoisonPill)`, :475-488), then `launchAll` supervises each `worker.run` on the outer supervisor.
Release is the reverse: worker pills (and each worker's inner Supervisor), executor
(`parallel`: `Supervisor(await)` joinAll/cancelAll; `sequential`: `Resource.pure`, nothing),
`doneR.set(true)`, `terminationLatch.complete(())`, outer supervisor (join or cancel workers).

## CE-0090 (found by reading, then reproduced)

A submission checks only `doneR` (:293-295). The worker stops taking after the pill (:461-469).
`doneR` is set only after the executor release. With `parallel(await = true)` the executor release
waits for running tasks, so a submission during that wait is accepted and lost (Future never
completes; a cancel action for it waits forever). `parallel(await = false)`: same window while
the release cancels tasks (about 70 ms measured with a scratch program; the release took 69 ms with
one canceled task). `sequential`: no executor Supervisor; first scratch run threw
`IllegalStateException` as promised.

Scratch run 1 (default runtime, submit 50 ms after the release started, Future read 2 s later):
parallel await=true and await=false: Future `None`; sequential: threw.
Gotcha: `IO.fromFuture` is not cancelable, so `.timeout` around it does not fire for a Future
that never completes; the first scratch program hung for 10 minutes. Read `future.value` instead.

Reproducer `reproducers/CE-0090/Repro.scala`: v3.7.1 and series/3.x (3.7.1-89-de84c01): 50/50
TestControl seeds and 50/50 default-runtime runs lost; `await = false` run printed "threw" (timing).

## Upstream test that cannot fail

`tests/shared/src/test/scala/cats/effect/std/DispatcherSuite.scala:500-517` "reject new tasks
while shutting down" ends its `for` with `yield fail("fail")`. `fail` throws inside `map`, so the
program is `Left` in every run and `assert(r.isLeft)` always holds, whether the submission throws
or not. It runs for all dispatchers through `common` (:155, :289), including `parallel(await = true)`.

## Duplicate search (read-only gh)

See `bugs/CE-0090.yaml` field `duplicates`. Related: #3501 (self-release), PR #3579, #3701,
#3981, #2448, #4069. No issue about this window.

## Other observations (not bugs, or known)

- A canceled dispatched effect never completes its `Future`: `poll(fe.guarantee(...)).redeemWith`
  (:316-320) does not run on cancel. Known (#2448, "self cancellation ... prevent the dispatch call
  from ever returning").
- `sequential`: the cancel action of a running task waits for the task (`Executor.inplace`,
  :499-505, comment :233-235); queued tasks cannot be canceled (#4069, open, known).
- Parallel mode picks a worker with `ThreadLocalRandom.current().nextInt(Cpus)` (:327). For a
  replay difftest the Scala runner must make this deterministic: run the JVM with
  `-XX:ActiveProcessorCount=1` (then `Cpus = 1`, worker 0 always). The model takes the worker
  choice as an input.
- The outer Supervisor has `checkRestart = always`: a worker that ends (after the latch) is
  restarted until the outer Supervisor's own `doneR` is set; each new incarnation sees the worker's
  `doneR = true`, waits on the completed latch, cedes and ends (:465-469 comment).

## Scope decision for this session

Not done in this session: the Lean mirror, the difftest ops, properties, witnesses, battery. Reason:
an exact replay difftest needs an exact mirror of `Supervisor` (both the `checkRestart = None` and
the restart paths, `applyForAsync`), which track V writes in parallel; and the user asked to limit
quota use. QUESTIONS.md Q6 records the default.
