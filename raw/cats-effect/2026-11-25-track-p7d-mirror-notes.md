# Track P7D, part 2: Dispatcher mirror, difftest, properties (2026-11-25)

Source: own work on top of track V's `Std/Supervisor.lean` (decision 66). Do not edit.

## Mirror (`Std/Dispatcher.lean`, namespaces 90 closures, 91 descriptors)

- `Resource#fold` is plain Scala on `Bind`/`Pure`; only `Eval` and `Allocate` make `IO` nodes. So
  `impl(...).use(f)` is a nesting of track V's `Supervisor.useIO` (outer `always`, executor, one per
  worker) and `bracketFull`s for the `Resource.make`s (`awaitTermination`, `termination`, each
  worker), then `ReadEC.flatMap(...)`. Track V's `useK` calls the `use` function inside the same
  closure call, so passing "the rest of the fold" as `f` gives the exact `IO` term.
- `Resource.make(acq)(rel)` = `Allocate(_ => acq.map(a => a -> rel(a)).map { case (a, r) => (a, _ => r) })`:
  two `Map`s; the release runs through track V's `SLam.relK`.
- Exact terms checked in the sources: `ifM` = `flatMap(if ...)` (cats `FlatMap.scala:142`);
  `>>` = `flatMap(_ => fb)` by name; `*>`/`<*` = `IO#productR`/`productL` (`IO.scala:900-904`,
  `IOAsync` overrides); `voidError` = `ApplicativeError#voidError` = `handleError(fu)(const(()))`
  = `IO#handleError` = `handleErrorWith(t => IO.pure(...))`; `redeemWith` = `attempt.flatMap(fold)`;
  `IO.defer` = `delay(thunk).flatten` (2 nodes); `UnsafeAsyncQueue.take` = `IOCont(body)` with
  `lift` = identity (`IOFiber` passes `FunctionK.id`).
- The impure entry points are one `IO.delay` thunk each (atomic in the model and in the Scala
  difftest, which calls them in `IO(...)`). `Promise` = a `Ref` cell `pair forget result`;
  `onComplete(reportFailure)` of `unsafeRunAndForget` runs at once on the parasitic EC: a failure
  completion emits `UserEffect.report`.
- `ThreadLocalRandom.nextInt(Cpus)` is an input list `cs` (a cell made in `kEc`).
- `sequentialCancelable` / `Executor.sequential`: `private[std]`, only the Cats Effect tests use
  them; excluded (inventory reason `internal:`).
- Codec lesson (track V's): keep `Sup.toVal` (fields), not the supervisor object reference, in
  closure fields.

## Difftest

- Ops `dUse`, `dSubmit`, `dForget`, `dCancel`, `dPoll` (format v2). `run.sh` starts the JVM with
  `-XX:ActiveProcessorCount=1` (so `Cpus = 1`; `dUse` checks it). `dPoll` = `Future#value` as a
  value (`None` → left unit; `Success(v)` → right(right v); user failure → right(left code);
  library failure → right(left unit)). `IO.fromFuture` is not cancelable (a lost Future hangs the
  harness), so the harness never waits on a Future.
- Template `tpl_disp` (own RNG `difftest-dispatcher:<seed>:<i>`, `p_disp`). First 300 cases: all
  agree. Cost: a `Supervisor` map counter of 5 makes the Lean side replay 120 orders (66 s for one
  case); the template keeps at most 3 accepted submissions and 2 cancels per scenario (k! ≤ 6).
  This is a cost limit, not an agreement limit (no case disagreed).
- Found by a generated case (both sides agreed): a submission made before the release but not yet
  taken is dropped by `parallel(await = true)` and the worker dies with
  `IllegalStateException: supervisor already shutdown` (reported by both sides). → CE-0091.
- Fixed cases `difftest/cases/dispatcher.jsonl`: 68, all agree.

## CE-0091

Reproduced: v3.7.1, series/3.x (de84c01), series/3.7.x (2f94201): parallel 0/50 TestControl
seeds, about 10-17/200 real runs; sequential 50/50 and 200/200. Issue #3506 was closed as fixed in
3.4.9 with this shape; the current #3506 test waits for the start (`latch.get`).

## Kernel cost and chunks

- `decide +kernel` on a full Dispatcher run: about 0.6 s and 25-60 MB per micro-step; the first
  ~100 steps (resource allocation: three Supervisors) are the most expensive. Track V's harness
  costs the same per step (measured: 30 steps, 21 s, 2.0 GB). A 300-step run: 8.4 GB; 389 steps:
  10 GB, 2:33.
- Chunks: the state between two tasks (`cur = none`) prints with `Repr` as a parsable Lean term
  (62 KB at step 189); a state inside a task (`cur = some loop`) does not parse. `runP_add`
  (`runSchedStateP (a + b) cs s = runSchedStateP b (cs.drop a) (runSchedStateP a cs s)`) composes
  the chunks. From a literal state, 200 steps cost 2.9 GB; the first chunk (about 100-130 steps)
  about 2 min and 5.2-6.0 GB; later chunks 5-40 s, ≤ 2 GB.
- `decide +kernel` with a `let` in the statement timed out in the elaborator (isDefEq heartbeats);
  repeat the term instead.

## Upstream test that cannot fail (second one)

None new. (The first: "reject new tasks while shutting down", see the part-1 note.)
