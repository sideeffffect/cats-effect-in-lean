# Track M (Phase 6, batch 6.2): `memoize` notes

> Source: own work on Cats Effect v3.7.1 source, Lean model runs, scala-cli runs, `gh` searches (read-only)
> Collected: 2026-11-10
> Published: 2026-11-10

## Dispatch

- `IO#memoize` (`IO.scala:944-945`) = `Concurrent[IO].memoize(this)`. `IOAsync` (`IO.scala:1996-2180`) does not override `memoize`, `never`, `fromEither`, `flatten`. So the body is the kernel default `GenConcurrent#memoize` (`kernel/.../GenConcurrent.scala:43-112`). No IO twin.
- `Resource` overrides `memoize` (`Resource.scala:1479-1480`: `fa.memoizedAcquire.map(Resource.eval(_))`; `memoizedAcquire` at `:792-803` calls `F.memoize`). Different body; not mirrored (track Res owns `Resource`).
- `IO.ref(a)` = `IO(Ref.unsafe(a))` = `SyncRef` (`Ref.scala:314`); `get`, `update`, `modify` are one `F.delay` each (`kernel/jvm-native/.../SyncRef.scala:30`, `:65-72`, `:86-94`). `SyncRef` does not override `flatModifyFull` (`Ref.scala:140-141`: `F.uncancelable(poll => F.flatten(modify(f(poll, _))))`).
- `IO.deferred` = `IO(new IODeferred)` (`IO.scala:1824`).
- `Outcome.embed(x)` = `fold(x, F.raiseError, identity)` (`Outcome.scala:73-74`).

## History of the code (git, read-only)

- `git log -L` on the Finished case: commits 46d03eea3e (Concurrent.memoize), 36101c1a43 (propagate cancelation), 3128049d7c (2023-01-07, "First try at redesigned memoize", PR #3351, released in v3.4.5), 61c462d391 (2023-02-22, "Use Ref#flatModifyFull in some places", v3.5.0).
- Before PR #3351 the slow path was `case other => other -> poll(get)`: a `Finished` state ran its result after `poll`. PR #3351 made the case `finished -> fromEither(result).flatten` inside `uncancelable { poll => state.modify {...}.flatten }`; no poll. 61c462d391 kept it in `flatModifyFull`.
- `memoize` body is the same on v3.7.1, `series/3.x` (3.7.1-89-de84c01) and `series/3.7.x` (3.7.1-15-2f94201).

## CE-0030 finding

- `fa` cancels itself → `Finished(Right(productR(canceled)(never)))`.
- `get` fast path (`state.get` sees Finished, line 108) runs `canceled *> never` unmasked → Canceled.
- `get` slow path (`state.get` sees Unevaluated/Evaluating; then `flatModifyFull` sees Finished, lines 91-92) runs it inside the mask → `canceled` is ignored, `never` waits forever, cancel of the fiber waits forever.
- Lean model predicted it first (one preemption at micro-step 35, 36 or 37 of `twoGets` with `fa = IO.canceled`; 79 micro-steps). Then scala-cli spike (`spikes/memoize/Spike.scala`): TestControl with thresholds (1,2): 20 + 30 of 200 seeds had a hung `get`; default thresholds: 0 of 200.
- Real runtime (`spikes/memoize/RealRuntime.scala`, 16 CPUs, default config, machine loaded by other builds): 2,098 hung of 100,000 runs.
- Reproducer `reproducers/CE-0030/Repro.scala` (TestControl, 200 seeds per row): IO#memoize 50/53/38 of 200 at (1,2)/(1,4)/(2,4), 0 at (512,1024); a copy of the kernel code gives the same counts; the fixed twin (`poll` in the Finished case) 0 everywhere. Same on series/3.x and series/3.7.x.

## Duplicate search (2026-11-10)

- `gh search issues 'memoize' -R typelevel/cats-effect`: #3513, #3527, #4620, #3474, #3757, #3819, #3764, #3348, #1620, #802, #3079, #2728, #2291, #1519, #1576, #1111, #1619, #78, #120, #530, #1116.
- Related: #1519 (closed 2021) "F.memoize(F.canceled) deadlocks and… really shouldn't" — the sequential case, fixed before the race existed; #3348 (doc vs implementation) → PR #3351; #802 (CE2 body).
- No result: 'memoize hang', 'memoize cancel', 'memoize deadlock', 'memoize flatModifyFull', 'memoize uncancelable', 'memoize never', 'memoize self-cancel', 'memoize Finished', 'memoize canceled'.
- 'flatModifyFull': only #3370 (RFC for the method).
- PRs 'memoize': #4105, #3890, #3351, #3518, #3080, #2729, #1204, #1484, #1552, #537, #544 and older; none changes the Finished case.

## Difftest (format v2 ops `memoize`, `memoGet`)

- Scala: `Prog.Memoize(e)` = `run(e).memoize.map(get => VMemo(h.newMemo(get)))`; `Prog.MemoGet(m)` = the stored `IO[Val]`. Value `{"t":"memo","id":n}` (output only).
- Lean: `Memoize.memoizeIO src` + `Map(memoHandle)`; the handle value is the `get` code (`Eff.get r src 0`). New internal trace events `deferredH` and `memoH`: the mirror makes model `Deferred` cells, so the glue renumbers `Deferred` handles (before, a model `Deferred` id was printed as is) and memo handles.
- Fixed cases `difftest/cases/memoize.jsonl` (150, `gen_memo.py`), 150 agree; 3 of them end `blocked` in both (CE-0030 in replay mode, thresholds (1,4), found by a random search: 16 of 3,000 schedules).
- Generator: `tpl_memo` (weight 0.4; 1.0 and 0.5 pushed a static share in `selftest.py` below its minimum, N = 400 is noisy) and `memoGet`. Selftest minimum for `memoize`/`memoGet`: 1 %.
- Depth run: `opcount.py --seeds 1 2 3 --n 36000 --chunk 6000 --ops memoize memoGet --boost tpl_memo=40` with the base weight 1.0 at that time (= `--boost tpl_memo=100` with the base 0.4): see the article for the counts.

## Smoke tests (`test/Phase6/MemoizeSmoke.lean`, native `#guard`, about 3 min)

- 9 `fa` × 400 random schedules (preempt 1/4), fuel 3,000.
- Stuck runs (blocked with a Finished memo), v3.7.1: canceled 9, cede-canceled 5, unc-canceled 6, all others 0. Fixed twin: 0 for all.
- `memoizeGetsAgree`: 0 violations; completed runs: 400 for all but canceled 391, cede-canceled 395, unc-canceled 394 (the stuck ones), never 0.
- `memoizeAtMostOnce`: max counter 1 for all 9.
- Wrong function (a `get` that is `fa` itself): agree fails for `fa = IO.ref(0)` (two cells), counter = 2.
