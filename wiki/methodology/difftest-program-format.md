# Difftest program format v0 and Scala runner

> Sources: own design and implementation in `difftest/` (Phase 3 steps 1–2) and `tools/Difftest/` (Lean side), run 2026-11-10 against cats-effect 3.7.1; IO.scala, IOFiber.scala, IORuntime.scala, TestControl.scala at v3.7.1; first `cediff` replay runs (2026-11-10)
> Raw: [First difftest agreement notes](../../raw/project-decisions/2026-11-10-first-difftest-agreement-notes.md); [Difftest runner notes](../../raw/project-decisions/2026-11-10-difftest-runner-notes.md); [Lean decoder notes](../../raw/project-decisions/2026-11-10-lean-difftest-decoder-notes.md); [Phase 0 decisions](../../raw/project-decisions/2026-11-10-phase0-decisions.md)

## Overview

This is the shared test-program language for the difftest. Scala and Lean read the same JSON.
The Scala runner is in `difftest/`. The Lean decoder, translation and replay run are in `tools/Difftest/` (section "Lean side").
Each AST node maps to **one fixed IO term** (table below). The Lean model must mirror these terms, not only their meaning, because replay compares task-level schedules.
Format version: `"v":0`. Any change to a node, a user function or an event is a new version.

## Values

JSON objects with a tag `t`.

| Value | JSON |
|-------|------|
| unit | `{"t":"unit"}` |
| bool | `{"t":"bool","v":true}` |
| nat | `{"t":"nat","v":3}` (0 ≤ n ≤ 9·10^15) |
| pair | `{"t":"pair","a":V,"b":V}` |
| either | `{"t":"left","v":V}`, `{"t":"right","v":V}` |
| outcome | `{"t":"succeeded","v":V}`, `{"t":"errored","code":n}`, `{"t":"canceled"}` |
| handles (output only) | `{"t":"fiber","id":n}`, `{"t":"ref","id":n}`, `{"t":"deferred","id":n}` |

- Errors are `UserError(code)` with a nat code. An error that is not a `UserError` (harness or CE internal) prints as `{"t":"errored","exn":"Class: message"}`. A generated program must never produce it.
- Handles are made only at run time. The decoder rejects handle literals in the input.
- Handle ids count from 0 in creation order, per kind. Fiber handle 0 is the root fiber (replay mode). `start` and `racePair` (the losing fiber) give new fiber handles.

## Atoms and binding

- An **atom** (argument position) is a value literal or a variable `{"t":"var","x":"name"}`.
- Binding is by name with lexical scope and shadowing: `bind`, `handleErrorWith`, `guaranteeCase`, `case`, `split` bind value variables; `uncancelable` binds a poll name.
- The decoder checks scope: unbound variable, a poll used as a value, or `poll` with a name that is not a bound poll is a decode error.
- A poll can escape its `uncancelable` through a `start` in the body (the "escaped poll" case). This is allowed.

## Programs

Each program is `{"op":...}`. Interpretation is Scala at v3.7.1. `I(p)` is the interpretation of `p`, `⟦a⟧` is the value of atom `a`. `emit(e)` appends event `e` to the trace (a plain side effect inside the given `delay`).

| op | fields | IO term |
|----|--------|---------|
| `pure` | `v`: atom | `IO.pure(⟦v⟧)` |
| `raise` | `code`: nat | `IO.raiseError(UserError(code))` |
| `delay` | `fn`: nat, `arg`?: atom (default unit) | `IO.delay(call(fn, ⟦arg⟧))` |
| `bind` | `x`, `e`, `k` | `I(e).flatMap(x => I(k))` |
| `seq` | `ps`: non-empty list | `I(p1).flatMap(_ => I(p2)).flatMap(_ => …)` (left-nested) |
| `map` | `e`, `fn` | `I(e).map(v => call(fn, v))` |
| `handleErrorWith` | `e`, `x`, `k` | `I(e).handleErrorWith { case UserError(c) => I(k)[x := nat c]; case t => IO.raiseError(t) }` |
| `attempt` | `e` | `I(e).attempt.map(Right(v) ↦ right v; Left(UserError c) ↦ left (nat c); other ↦ throw)` |
| `uncancelable` | `poll`: name, `body` | `IO.uncancelable(poll => I(body))` |
| `poll` | `poll`: name, `e` | `poll(I(e))` |
| `onCancel` | `e`, `fin`, `tag`? (default 0) | `I(e).onCancel(IO.delay(emit fin) *> I(fin).void)` |
| `guaranteeCase` | `e`, `x`, `fin`, `tag`? | `I(e).guaranteeCase(oc => ocVal(oc).flatMap(o => IO.delay(emit fin+oc) *> I(fin)[x := o]).void)` |
| `canceled` | – | `IO.canceled.as(unit)` |
| `cede` | – | `IO.cede.as(unit)` |
| `never` | – | `IO.never` |
| `start` | `e` | `I(e).start.map(f => fiber(handle f))` |
| `join` | `f`: atom | `fib.join.flatMap(ocVal)` |
| `cancel` | `f`: atom | `fib.cancel.as(unit)` |
| `racePair` | `a`, `b` | `IO.racePair(I(a), I(b)).flatMap(Left(oc, fb) ↦ ocVal(oc).map(o => left(pair(o, fiber fb))); Right(fa, oc) ↦ … right(pair(fiber fa, o)))` |
| `sleep` | `ms`: nat | `IO.sleep(ms.millis).as(unit)` |
| `refNew` | `v` | `IO.ref(⟦v⟧).map(r => ref(handle r))` |
| `refGet` | `r` | `ref.get` |
| `refSet` | `r`, `v` | `ref.set(⟦v⟧) *> IO.delay { emit set; unit }` |
| `refModify` | `r`, `fn` | `ref.modify(s => call(fn, s) must be pair(next, out) ↦ (next, out))` |
| `deferredNew` | – | `IO.deferred[Val].map(d => deferred(handle d))` |
| `deferredGet` | `d` | `d.get` |
| `deferredComplete` | `d`, `v` | `d.complete(⟦v⟧).flatMap(ok => IO.delay { emit complete; bool ok })` |
| `async` | `cbs`: list, `fin`?, `tag`? | see below |
| `case` | `on`, `l`, `lk`, `r`, `rk` | either on `⟦on⟧`: left v ↦ `I(lk)[l := v]`, right v ↦ `I(rk)[r := v]` |
| `split` | `on`, `a`, `b`, `k` | pair on `⟦on⟧` ↦ `I(k)[a := fst, b := snd]` |

- `ocVal(oc)`: `Succeeded(fa)` ↦ `fa.map(succeeded)`; `Errored(t)` ↦ `IO.pure(errored code)`; `Canceled` ↦ `IO.pure(canceled)`.
- `async`: `IO.executionContext.flatMap(ec => IO.async(cb => IO.delay { id = next async id; emit asyncReg; for each callback i: sync ↦ fire now, later ↦ ec.execute(task "cb<id>.<i>" that fires); fin.map(f => IO.delay(emit fin) *> I(f).void) }))`. A callback entry is `{"when":"sync"|"later","ok":V}` or `{"when":…,"err":code}`. "Fire" means `emit cb` then `cb(Right v)` or `cb(Left UserError(code))`. So a test can call the callback 0, 1 or 2+ times, inside the registration or as a separate schedulable task, with or without a finalizer.
- A wrong value shape (for example `inc` on a pair, `join` on a ref) throws `TypeError`. It is not a `UserError`, so `handleErrorWith` and `attempt` rethrow it. Generators must make well-typed programs.

## User function table

`call(fn, v)` first emits `{"ev":"call","fn":fn,"arg":v}`, then applies the function. Lean must implement the same table.

| id | name | argument → result |
|----|------|-------------------|
| 0 | id | x → x |
| 1 | unit | x → unit |
| 2 | inc | nat n → nat n+1 |
| 3 | raise | nat c → raises `UserError(c)` |
| 4 | dup | x → pair(x, x) |
| 5 | incOld | nat n → pair(n+1, n) (for `refModify`: new state, old value) |
| 6 | not | bool b → ¬b |
| 7 | isZero | nat n → bool (n = 0) |
| 8 | fst | pair(a, b) → a |
| 9 | snd | pair(a, b) → b |

## Trace events

| event | when |
|-------|------|
| `{"ev":"call","fn":k,"arg":V}` | each user-function call (`delay`, `map`, `refModify`) |
| `{"ev":"fin","op":"onCancel"\|"async","tag":n}` | an `onCancel` or `async` finalizer starts |
| `{"ev":"fin","op":"guaranteeCase","tag":n,"oc":O}` | a `guaranteeCase` finalizer starts, with the outcome |
| `{"ev":"set","ref":i,"v":V}` | after a `refSet` |
| `{"ev":"complete","deferred":i,"v":V,"ok":b}` | after a `deferredComplete` |
| `{"ev":"asyncReg","async":i}` | `async` registration runs |
| `{"ev":"cb","async":i,"i":k}` | callback k of async i is called (before the call) |

## Test case and run modes

Input line: `{"v":0,"id":"…","mode":"replay","choices":[…],"maxSteps":n,"prog":P}` or `{"v":0,"id":"…","mode":"testcontrol","seed":n,"maxSteps":n,"prog":P}`. `maxSteps` default is 10,000.

**replay** (primary, decision 3). Scripted `ExecutionContext` and virtual-time `Scheduler` in `IORuntime(ec, ec, scheduler, () => (), IORuntimeConfig())`. The root runs through `unsafeRunFiber`.

- Ready list: tasks in enqueue order. Labels at first enqueue: `f<k>` for IOFibers (root `f0`, then creation order), `x<k>` for external cancelers, `cb<a>.<i>` for callback tasks, `t<k>` for timer tasks.
- A choice `n` runs ready task `n mod size` as one step (one `IOFiber.run()` or one callback/timer task).
- A choice `{"cancel":h}` runs `fiber(h).cancel` as a new fiber `x<k>` at once, as one step (decision 2). It also works when the ready list is empty. An unknown handle gives a `{"cancel":h,"skipped":true}` log entry and no step.
- When the choices run out, the runner picks index 0 (FIFO) and sets `fifoFrom` to that step.
- Time moves only when nothing is ready: all timers with the earliest due time move to the ready list in creation order (log entry `{"advance":ms,"woken":[…]}`).
- Stop: the root has an outcome (after the current task), or `blocked` (nothing ready, no timers), or `fuel` (`maxSteps` reached).

**testcontrol** (secondary). `TestControl.execute(prog, seed = base64(seed as decimal text))`. Loop: `results`; else `tickOne` (one step); if nothing ran, `isDeadlocked` → `blocked`, else `advance(nextInterval)`. At `maxSteps` the outcome is `inconclusive` (decision 4). No external cancel in v0.

Output line: `{"v":0,"id","mode","outcome","trace","steps","time","schedule","fifoFrom","fibers","pending","failures"}`.

- `outcome`: `succeeded`/`errored`/`canceled` of the root, or `blocked`, `fuel`, `inconclusive`.
- `schedule`: replay: list of `{"step","ready","pick"|"cancel","task"}` and `advance` entries; testcontrol: `{"seed":n}`.
- `fibers`: fiber handle → task label. `pending`: ready tasks + timers left at the end (a leak signal). `failures`: `reportFailure` calls.
- A bad line gives `{"v":0,"id":…,"error":"decode: …"}`.

## How to run

- Tests: `cd difftest && sbt -batch test` (golden files `cases/*.expected.jsonl`, rerun determinism, hand-checked facts). About 12 s from clean.
- Update golden files: `sbt -batch -Ddifftest.update=true test`, then review the diff.
- Run cases: `difftest/run.sh FILE.jsonl …` or `… | difftest/run.sh` (stdin). It caches the class path and runs plain `java`: about 4,500 cases/s. `sbt run` does not forward stdin in batch mode.
- Other CE version: `sbt -Dce.version=<version> test`.
- Lean side: `lake build Difftest cediff`, then `lake exe cediff difftest/cases/basic.jsonl`. Compare with Scala: `python3 difftest/py/drive.py check --lean "lake exe cediff" difftest/cases/*.jsonl` (only the input files, not `*.expected.jsonl`).
- Generated cases, driver, shrinker: `difftest/py/` ([Differential testing](differential-testing.md), sections Generator and Driver).
- CI: job `difftest` runs `sbt -batch test` (JDK 21), `python3 difftest/py/selftest.py`, then builds `cediff` and requires agreement (`drive.py check` on the fixed files, `corpus`, `run` on 3 × 2,000 replay cases); the `lean` job runs the Lean side on the fixed case files (`basic`, `sched`, `deferred`, `racesleep`).

## Lean side

Code: `tools/Difftest/` (`lean_lib Difftest`, `lean_exe cediff`). It is test code, not part of the `CatsEffectInLean` library.

- `Prog.lean`: AST and decoder. Same rejections as `Json.scala`. Names become de Bruijn indices (0 = innermost; `split` binds `b` at 0, `a` at 1). `seq` becomes left-nested binary `seq`; `seq [p]` is `p`.
- `Translate.lean`: `tr p node env vw` gives the root `Model.IO` term with the same constructor nesting as `Interp.run`. Examples: `canceled` = `Map(Canceled, _ => unit)`; `never` = `IOCont(body)` (`IO.scala:2198`, `Async.scala:168`, `IO.scala:1418-1431`); `guaranteeCase` = `Uncancelable(poll => FlatMap(HandleErrorWith(OnCancel(UnmaskRunLoop(e), fin(canceled)), onError), flatTap))` (`IO.scala:523-530`, `605-606`, `474`, `967-971`); `async` = `FlatMap(ReadEC, ec => IOCont(…))`; `join` = `FlatMap(IO.joinOf t oc, ocVal)`; `refNew` = `Map(Delay(Ref.unsafe v), handle)`.
- State read at build time: `vw` is the `View` when Scala builds the term. `join`/`cancel` read the fiber outcome (`_join`/`_cancel`), `deferredGet` reads the cell. Scala builds three sub-terms eagerly that the model builds later in a closure (the `onCancel` finalizer, the `this` of `guaranteeCase`, the `async` finalizer); these closures capture a snapshot (`snapVal`).
- `Closure.lean`: each Scala lambda is `Fn.user (Clo.encode ⟨node, lam, vals⟩)`: pre-order node number, lambda kind (`Lam`, 49 kinds), captured values. The encoding is lossless (`Clo.decode?`).
- `Env.lean`: `denv p id arg vw` runs a closure and returns the model result plus trace events and `reportFailure` calls. `userEnv p : UserEnv` turns the events into `UserEffect.emit` effects (`TraceEv.toVal`).
- `Replay.lean`: runs the root term on `Model.Sched` (`counterMaskModel`, default `Config`) one micro-step at a time, and keeps what Scala prints but the model does not hold: fiber handles (decision 14: handle order of `h.fiberHandle`; a cancel choice maps the handle to the model id when it is used), task labels (`f<k>`, `x<k>`, `cb<a>.<i>`), async ids, the `cb` event of a `later` callback task, and the `failures` list.
- Errors: `UserError(c)` is `Err.code = c + 2`; code 0 is `TypeError`; code 1 is a harness error.
- Trace: `asyncReg`/`cb` events hold the `ContState` id; internal events `handle` (`h.fiberHandle`) and `cbLater` (a `later` callback). The replay glue renumbers asyncs and fibers to the Scala ids.
- `Tests.lean`: 62 `#guard` checks that run during `lake build Difftest`.
- `lake exe cediff [FILE…]` (stdin if no file): one line per case. Replay case with supported ops: the Scala output fields plus `"compare":[…]` (the fields that the driver compares; now all nine). Otherwise `{"v":0,"id","mode","outcome":"unsupported","size":n,"unsupported":[ops]}` (`mode:testcontrol` for testcontrol cases, decision 15) or `{"v":0,"id","error":"decode: …"}`. Exit 1 if a case is rejected. Speed: 2,000 cases in 0.14 s.

**What the model lacks** (these ops are reported as `unsupported`, never guessed). `racePair` and `sleep` run since 2026-11-10 ([Scheduler model](../cats-effect/scheduler-model.md)); the replay glue labels timer tasks `t<k>`, prints `advance` entries, `time`, and counts timers in `pending`:

| Gap | Ops | Needed in the model |
|-----|-----|---------------------|
| testcontrol mode | all | the bounded schedule search with a `complete` flag (decision 15) |
| `Fn.user` has no captured values | none (workaround) | none (the encoding works); cleaner: `Fn.user id env` |
| `Val` cannot hold an `IO` (`async` returns `Option[IO[Unit]]`, `IO.defer` returns an `IO`) | none (workaround) | none: a marker value, and the next closure rebuilds the term |

## Limits of v0

- No `both`, `race`, `bracket`, `Resource`, `IO.blocking`, `evalOn`, `timeout`, `memoize`, `std` structures.
- No recursion or loops in the language; programs are finite trees.
- Replay labels only the root and handled fibers by handle. CE-internal fibers (none in v0 ops except the `racePair` pair) get plain `f<k>` labels.
- Testcontrol mode has no external cancel, no virtual time output, no failure list.
- Not tested yet against a `series/3.x` build.

## See Also

- [Differential testing](differential-testing.md)
- [TestControl and schedule replay](../cats-effect/testcontrol.md)
- [Scheduler model (multi-fiber, replay)](../cats-effect/scheduler-model.md)
- [Project plan](project-plan.md)
- [Semantics of CE3](../cats-effect/semantics.md)
- [Agent workflow and review protocol](agent-workflow.md)
