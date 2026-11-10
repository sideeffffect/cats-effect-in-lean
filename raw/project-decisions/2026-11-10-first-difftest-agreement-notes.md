# First difftest agreement: `cediff` runs replay cases on the model (own note)

> Source: own work in this repository (`tools/Difftest/Replay.lean`, `tools/Difftest/{Translate,Env,Main}.lean`, `CatsEffectInLean/Model/{Syntax,Step,State}.lean`, `difftest/py/drive.py`, `.github/workflows/ci.yml`), Lean v4.35.0, runs against Cats Effect 3.7.1 (`difftest/run.sh`); Scala sources read at v3.7.1 (`IODeferred.scala`, `CallbackStack.scala` (jvm-native), `IO.scala`, `IOFiber.scala`, `Ref.scala`)
> Collected: 2026-11-10
> Published: 2026-11-10

## What was built

- `lake exe cediff` now runs each replay case whose ops the model mirrors. It prints the Scala replay line: `outcome`, `trace`, `steps`, `time`, `schedule`, `fifoFrom`, `fibers`, `pending`, `failures`, plus `compare` (the fields that the driver compares). All nine Scala fields are compared.
- Still `unsupported`: cases with `racePair` or `sleep` (no `RacePair`/`Sleep` mirror), and all testcontrol cases (`mode:testcontrol`, decision 15).
- Driver: `compare` uses the `compare` list of the Lean line (outcome and trace always). New subcommand `drive.py check FILE…` (fixed case files; fails unless each case agrees or is unsupported).
- CI job `difftest`: installs Lean (`lean-action`, `auto-config: false`), builds `cediff`, runs `check` on `basic.jsonl` + `sched.jsonl`, the corpus, and `run --seeds 1 2 3 --n 2000 --modes replay`. Any mismatch, harness error or hang fails the job.

## Model changes (additive, decision 13)

- `IODeferred` mirror (Phase 2 step 9, part): `RtFn.deferredDefer`, `deferredFlatten`, `deferredAwait`, `deferredUnc`, `deferredReg`, `deferredSel`, `deferredClear`, `deferredComplete`; `Heap.deferreds : List DeferredCell`; `UserEffect.allocDeferred`; `View.deferreds`; `IO.deferredGetOf`.
  - `get` = `cell.get()` at build time (`IODeferred.scala:71`): `IO.pure(a)` or `initial` = `IO.defer {…}` = `FlatMap(Delay(thunk), ev)` (`IO.scala:1296-1297`, `472`). The thunk returns a marker (`none`/`some a`); `deferredFlatten` builds the `IO` again (a `Val` cannot hold an `IO`; same trick as `joinReg`).
  - `await` = `IO.asyncCheckAttempt` (same shape as `_join`): push the waiter's `resume`, then `Left(Some(IO(clear())))` or `clear(); Right(value)`.
  - `complete`: CAS `initial → pure(a)`, then `callbacks(Right(a))`: newest first (the constructor callback is `null`), stack cleared (`CallbackStack.apply`).
  - Not mirrored: `pack` and the exact `clearCounter` value. JVM `clearHandle` nulls the node and returns `false`; `pack` only frees nulled nodes. The model removes the node at once. No observable difference.
- `DeferredCell` (State.lean) is now used by the step function.

## Translation changes

- `tr` takes the `View` of the moment when Scala builds the term. `join` = `IO.joinOf t (outcome)` then `flatMap(ocVal)`; `cancel` = `IO.cancelOf t (outcome)` then `as(unit)`; `deferredGet` = `IO.deferredGetOf`.
- Eager construction. Scala builds three sub-terms when the outer term is built, but the model builds them later in a closure: the `onCancel` finalizer (`*>` is by value), the `this` of `guaranteeCase`, and the `async` finalizer (built in the registration thunk). Building reads mutable state (`_join`/`_cancel`, `deferred.cell`). So these closures capture a snapshot (`snapVal`: fiber outcomes + Deferred cells) taken at Scala build time. `gcFinThen` does not need one: Scala builds `run(fin)` one iteration earlier, in a `FlatMap` over `Delay` (one iteration, nothing runs between).
- `refNew` = `Map(Delay(Ref.unsafe(v)), handle)` (`IO.scala:1822`); the thunk does `allocRef`. `deferredNew` = `Map(Delay(new IODeferred), handle)` (`IO.scala:1824`). `deferredComplete` = `FlatMap(Delay(rt complete), ok => IO.delay{emit; bool ok})`.
- Trace events go through `UserEffect.emit` (`TraceEv.toVal`). New internal events: `cbLater async i` (label of a `later` callback task), `failure e` (user `reportFailure`).

## Replay glue (`tools/Difftest/Replay.lean`)

- Runs `Sched.tick` one micro-step at a time (mask model `counterMaskModel`, default `Config`: thresholds 512/1024, as `IORuntimeConfig()`). After each micro-step it reads new emitted values, new runtime `reportFailure` events and new ready entries.
- Fiber handles (decision 14): handles in the order of `handle` events (root = 0). A `{"cancel":h}` choice maps `h` to the model id when it is used; an unknown `h` gives a skipped cancel (an id that no fiber has).
- Task labels: `labels` is aligned with `Heap.ready`. `f<k>` at the first enqueue, `x<k>` for a canceller, `cb<a>.<i>` for a later callback (index from `cbLater`).
- The `cb` event of a later callback is added when the task is picked (in Scala the task emits it, in the model the task is runtime code).
- `failures`: in one micro-step, user failures come before runtime ones. After a runtime `reportFailure` (`done`, `cancelationLoopFailureK`) the iteration runs no more user code, so the order is exact.

## Results

Replay mode, `drive.py run --modes replay`, generator `max_size` 40 unless noted.

| run | cases | agree | unsupported | mismatch |
|-----|------:|------:|------------:|---------:|
| seed 1, n 2000 | 2000 | 1588 | 412 | 0 |
| seed 2, n 2000 | 2000 | 1663 | 337 | 0 |
| seed 3, n 2000 | 2000 | 1616 | 384 | 0 |
| seeds 1-10, n 10000 | 100000 | 81663 | 18337 | 0 |
| seeds 11-20, n 10000, max_size 80 | 100000 | 80148 | 19852 | 0 |
| `basic.jsonl` + `sched.jsonl` | 33 | 29 | 4 | 0 |

- Total: 161,811 generated cases agree on all nine fields, 0 mismatches, 0 harness errors, 0 hangs.
- With both modes (driver default), each testcontrol case is `unsupported` (`mode:testcontrol`).
- Unsupported ops (cases that contain the op, seeds 1-10): `sleep` 13.0%, `racePair` 6.8%, either 18.3%. At max_size 80: 14.2%, 7.9%, 19.9%.
- Before this work, `join`, `cancel`, `refNew` and the three `deferred*` ops were also unsupported, and `cediff` ran nothing: 20 of the 27 cases of `basic.jsonl` had no unsupported op.
- Feature counts in the 1,588 agreeing cases of seed 1: outcome succeeded 726, errored 357, blocked 253, canceled 239, fuel 13; external cancel 192, skipped cancel 43, callback task 215, `pending` > 0 in 415, `failures` not empty in 91, more than one fiber 356, `complete` events 42, `set` events 45.
- Speed: `cediff` runs 2,000 cases in 0.14 s (compiled). In the driver, 100,000 cases: Scala 29 s, Lean 21 s (chunks of cases, one process per chunk). `lake build Difftest cediff` after a model change: a few seconds.

## Model bugs found

None. Every runnable case agreed on the first full run. The hand-checked scheduler examples (`SchedExamples.lean`) had already fixed the task-level details before this run.

Because 0 mismatches can also mean a blind harness, a mutation test was run: plant one bug in `Step.lean`, rebuild `cediff`, run seed 1 (n 10000, 8,153 runnable cases), count mismatches.

| mutant | mismatches | fields |
|--------|-----------:|--------|
| `done` calls pushed callbacks oldest first | 40 | steps, schedule, outcome, trace |
| no `reportFailure` in `cancelationLoopFailureK` | 216 | failures |
| no report of an unhandled `Errored` outcome | 130 | failures |
| `_cancel` on a masked suspended fiber does not `suspend()` again | 112 | outcome |
| `_cancel` never takes over a suspended unmasked fiber | 124 | outcome, trace, schedule, pending, steps |
| `Canceled` sets the flag only when unmasked | 44 | outcome, trace |
| `Start` puts the child at the front of the ready list | 187 | fibers, schedule, trace, outcome, steps |
| `UnmaskRunLoop` without the `self` check | 12 | trace, outcome, steps |
| second callback call overwrites the result | 250 | outcome, trace, failures |
| `Get` without the `monitorDeregister` finalizer | 0 | equivalent: changes only iteration counts |
| `Get` with a result ignores `shouldFinalize` | 0 | equivalent in replay: the loop-top check in the same iteration sees the flag first |
| `deferredReg` ignores a completed cell | 0 | equivalent in replay: the `IO.defer` thunk reads the cell in the same task |
| `complete` calls waiters oldest first | 0 | **coverage gap**: no case with 2+ waiters on one Deferred at `complete` |

## Gaps and open points

- `racePair`, `sleep` (timers), testcontrol refinement (decision 15) are not run yet.
- Coverage gap: two or more fibers waiting on one `Deferred` when it completes (the order of `CallbackStack.apply`). Needs a generator template (gen.py is owned by another agent).
- Iteration counts are not observable unless a task runs ≥ 512/1024 iterations (cancel check, auto-yield). No generated case reaches that; the equivalent mutants above show it.
- `failures` text for a non-`UserError` cannot match the Scala message (`TypeError: …`). Generated programs never produce one (decision 8).
- The corpus (`difftest/corpus/`) stays empty: there was no mismatch to shrink.
