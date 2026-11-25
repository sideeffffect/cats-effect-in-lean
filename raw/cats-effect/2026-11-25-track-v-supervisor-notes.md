# Track V (Supervisor) notes, Phase 7 batch 7.2 (2026-11-25)

Source: own reading of `std/shared/src/main/scala/cats/effect/std/Supervisor.scala` at v3.7.1
(`~/Projects/cats-effect`, detached at `v3.7.1`), cats-core 2.13.0 sources
(`cats/instances/list.scala`, `cats/data/Chain.scala`, `cats/Parallel.scala`, `cats/Foldable.scala`,
`cats/Traverse.scala`), `kernel/.../Resource.scala`, `kernel/.../Sync.scala`, own Lean, scala-cli
(difftest runner) and smoke runs.

## Source facts

- `Supervisor[IO](await)` = `apply(await, None)` → `F match { case asyncF: Async[F] => applyForAsync }`
  (`SV:128-139`). `IO` always takes the `Async` state (a `ConcurrentHashMap`). `applyForConcurrent`
  (`Ref[Map]` with a `null` sentinel) runs only for a `Concurrent` that is not `Async`; it is
  `private[effect]`, reachable from the difftest (package `cats.effect`).
- `checkRestart` is `private[std]`; the only caller is `Dispatcher` (`Dispatcher.scala:254`,
  `Some(_ => true)`).
- `Resource` shape: `Bind(Eval(F.ref(false)), doneR => Bind(Allocate(...), mapK))`; `use` folds it to
  `F.ref(false).flatMap(a => F.bracketFull(...)(useK)(relK))` (`R:156-196`).
- The release: `case (st, Succeeded) if await => doneR.set(true) *> st.joinAll; case _ =>
  doneR.set(true) *> st.cancelAll` (`SV:168-173`). So `await = true` cancels after an errored or
  canceled `use` body (deliberate: the `@param await` text describes the success case only).
- `supervise` (`SV:184-328`): `uncancelable`; `for` with `cleanup = state.remove(token)` desugars to
  `F.unique.map(token => (token, cleanup)).flatMap { case (token, cleanup) => ... }`.
- `None` monitor: `F.start(fa).flatMap(fib => F.start(fib.join.guarantee(fin)).as(fib))`: a second,
  internal "monitor" fiber per child; it is not in the map, and the close does not wait for it
  (after a close the monitor may still run `fin`: `done.set(true) *> remove`; harmless).
- `Async.add` = `put` then `doneR.get.map(!_)`: linearizable against the release (`doneR.set` then
  snapshot): an `add` that read `false` put its fiber before the snapshot.
- Restart protocol (`SV:187-288`): `currentR.set(newCurrent)` before `canceledR.get`; the wrapper's
  `cancel` sets `canceledR` before it reads `currentR`. So after `canceledR = true` at most one
  restart happens and the second `delegateF` read never sees another fiber (the `AssertionError`
  branch `SV:268-269` is unreachable under sequential consistency). `AssertionError` is `NonFatal`.
- Concurrent cancels of the same wrapper (user cancel and `cancelAll`) can both take the
  `fiber2 eq fiber` branch and run `fin` twice; `fin` is `done.set(true) *> remove` (idempotent), so
  nothing is observable.
- `cancelAll` = `allFibers.flatMap(_.parUnorderedTraverse(_.cancel).void)`: cats `List.traverse` with
  `ParallelF` (not a `StackSafeMonad`) = `Chain.traverseViaChain` (width 128, right-nested `map2`
  = `F.both(...).map`); `joinAll` = `traverse_` = `traverseVoidDirectly` (`productR` fold).
- The map order (`ConcurrentHashMap.values`, Scala `HashMap`) depends on identity hashes: an input.

## Model decisions

- Mirror `Std/Supervisor.lean` (namespace 80 closures, 81 descriptors, 82 Props harness). The
  supervisor is `Val.fn (SLam.obj s)`; `supervise` takes a source code; `ioOf` gives its program.
- Map cell = `pair (nat c) (listV entries)`, entries `pair (pair token (nat i)) fiber`; ghost
  insertion counter `c` and index `i` let the difftest name one order (`Env.supOrder` with
  `rankOrder`). `null` = `pair (nat c) none` (ghost counter kept).
- Token = a fresh model `Ref` cell (`F.unique` = `delay(new Token)`).
- Codec cost: closure ids that embed other closure references double in size per level. The first
  wrapper value embedded `fa`'s source, and a later `supervise` source embedded the earlier wrapper
  (it is in the difftest environment): exponential growth, 8 GB on a 4-`supervise` case. Fix: the
  wrapper captures only `(call, resultR, canceledR, currentR)` (as in Scala, it does not capture
  `fa`; `RCtx.toW`). Also `Call` does not hold the source.
- Restart-path difftest runs are still slow (about 30 ms per step: large ids decoded several times
  per closure call). Generator: restart scenarios at most 2 children, no nesting, maxSteps 150.
- Difftest library exception: `IllegalStateException: supervisor already shutdown` is printed as
  an exception (`Prog.userCodeV?`), and `drive.py` accepts it (`LIB_EXNS`) instead of calling the
  case a generator bug (it is the documented error of `supervise` after the close).
- External cancel of a restart wrapper handle: skipped on both sides (the wrapper is not an
  `IOFiber`; harness rule, `Runner.scala`).

## Wrong variants (not Cats Effect code)

1 `supervise` raises, 2 hangs, 3 drops (`start(IO.unit)`), 4 doubles, 5 factory raises, 6 factory
hangs, 7 release drops (sets `doneR`, no cancel/join), 8 `await = false` joins, 9 `add` ignores the
close, 10 `remove` never removes, 11 restart ignores `canceled`/`done`, 12 `await = true` cancels.
First smoke: variant 9 was not wired for the `Async` state (only `modAdd`); fixed.

## Difftest runs

- Run 1 (seeds 81-83 × 18,400, `--boost tpl_sup=12`, 12 processes): 55,200 cases, 48,227 agreeing
  per op (`supUse`, `supervise`), 12 mismatches (`steps`, `schedule`, `trace`). All 12 have 6-8
  `supervise` calls on one supervisor (nested children). Cause: the Lean side lists every map
  order of at most 5 entries; the Scala order comes from identity hashes, so with 6 or more entries
  it can be outside the list. Evidence: a rerun of the 12 cases gave 5 agreements (the Scala output
  varies from run to run with the identity hashes). Not a model bug. Fix: the generator makes at
  most 5 `supervise` per scenario (`sup_left`); run 2 uses the fixed generator.
