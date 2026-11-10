# Difftest runner v0, Scala side: build notes (own note)

> Source: own work in this repository (`difftest/`, Phase 3 steps 1–2), run on 2026-11-10 against Cats Effect 3.7.1
> Collected: 2026-11-10
> Published: 2026-11-10

## What was built

- `difftest/` sbt 1.12.1 project. Scala 3.3.7, cats-effect 3.7.1, cats-effect-testkit 3.7.1, ujson 4.4.3, munit 1.2.4 (test). `-Dce.version=...` changes the CE version (adds the Sonatype Central snapshots resolver when it is not 3.7.1).
- Program format v0 (JSON). Decoder with strict checks (unknown keys, unbound variables, poll misuse, handle literals, format version).
- Interpreter Prog → `IO[Val]`. Each AST node gives one fixed IO term.
- Replay mode: scripted `ExecutionContext` + virtual-time `Scheduler` in `IORuntime(ec, ec, scheduler, () => (), IORuntimeConfig())`. Choice list of ready-list indices and `{"cancel": h}` entries. FIFO when the list runs out (`fifoFrom` records the step).
- TestControl mode: `TestControl.execute(prog, seed = Some(base64(seed.toString)))`, loop `results` / `tickOne` / `isDeadlocked` / `nextInterval` + `advance`, step cap gives "inconclusive".
- 27 example cases in `difftest/cases/basic.jsonl` (made by `difftest/cases/gen_basic.py`), golden output in `basic.expected.jsonl`, munit suite `CasesSuite` (golden compare, rerun determinism, 6 hand-checked facts, decoder rejections). 35 tests pass.

## Measurements (this machine, JDK 21)

- `sbt -batch test` from clean: 12 s wall (9 s sbt task time). Warm: about 8 s.
- `difftest/run.sh FILE` (cached class path, plain `java`): 5,400 cases (27 cases × 200) in 1.2 s wall, about 4,500 cases/s, including JVM start. The first call runs sbt to export the class path (about 6 s).
- `sbt run < file` does not work: in batch mode sbt does not forward stdin to the forked JVM. Fix: `Main` takes file arguments; `run.sh` runs `java` directly.

## Findings

1. External cancel needs its own step type. It must run even when the ready list is empty (for example the root waits in `never` or in an `async` with no callback). The first version stopped with "blocked" before it read the cancel entry. Fix: the driver reads a `{"cancel":h}` entry first, before the "blocked" check.
2. `IO.unsafeRunFiber` is `private[effect]`. Code in package `cats.effect.difftest` can call it. It gives the root `IOFiber`, so the root is fiber handle 0 and can be canceled from outside.
3. The external canceler is a new `IOFiber` (`fib.cancel.unsafeRunFiber`). `unsafeRunFiber` enqueues it through `ec.execute`. The driver removes it and runs it at once as the cancel step. After that step the canceler often waits (for the target's finalizers), so it stays as a pending task `x<k>`.
4. Labels must be given at first enqueue. Giving a label after `execute` shifted the `f<k>` numbers. Fix: `ScriptedEC.nextLabel`.
5. `IO.canceled` inside `uncancelable` with no `poll`: the body continues and the fiber **succeeds** with the body result (case `uncancelable-canceled-continues`). With `poll(canceled)` the fiber ends canceled at once (case `poll-canceled`).
6. Two `later` callbacks on one `async`: the second call is ignored; both `cb` events are in the trace. A `sync` callback that runs before a queued `later` one wins; the `later` task stays pending after the root ends.
7. TestControl seed 1 and seed 2 give different interleavings of the two-fiber program, and different step counts (6 vs 7). The scripted FIFO run gives 6 steps.
8. The v0 runner does not read the TestControl virtual clock or its reported failures. In testcontrol mode the output has `time: null`, empty `fibers` and empty `failures`.
