# Batch 6.3 notes: `parTraverseN` mirror, difftest, properties

> Source: own Lean work (`CatsEffectInLean/Model/ParTraverse.lean`, `Props/Phase6/ParTraverse.lean`, `Proofs/Phase6/ParTraverseWitness.lean`, `tools/PtSmoke/Main.lean`), difftest runs, scala-cli walks of the real `IO` tree on CE 3.7.1; sources at v3.7.1: `kernel/.../GenConcurrent.scala:113-251`, `MiniSemaphore.scala:17-88`, `Ref.scala:123-124`, `jvm-native/.../SyncRef.scala`, `IODeferred.scala:20-80`, `IO.scala:1593-1600`, `:1996-2175`; cats-core 2.13.0 (`instances/list.scala:121-174`, `Traverse.scala:289-308`, `FlatMap.scala:113-143`, `Apply.scala:222-223`, `Parallel.scala:283-294`), `kernel/.../instances/GenSpawnInstances.scala:26-70`
> Collected: 2026-11-14
> Published: 2026-11-14 (own research note)

## Facts

- `IO.parTraverseN` = `_asyncForIO.parTraverseN`; `IOAsync` does not override it, so there is one body (the kernel default). No twin.
- The inventory already had the rows (`core.IO.parTraverseN`, `kernel.GenConcurrent.parTraverseN`, `kernel.MiniSemaphore.*`, `kernel.SyncRef.*`, `core.IODeferred.*`). The cats-core helpers are outside the inventory scope (kernel, core, std).
- `IOAsync` is a `StackSafeMonad`, so `List.traverse` = `map(foldLeft(pure(Chain.empty))(map2(acc, f(a))(_ :+ _)))(_.toList)` and `f(a)` runs while the fold runs. `map2` = `flatMap(fa)(a => map(fb)(...))` (no `IOAsync` override). Checked by printing the real `IO` tree (reflection on the `IO` case classes): `Map(FlatMap(Pure(Chain()), fn), fn)`.
- `parTraverse_` in `cancelAll` uses `ParallelF`: a balanced `runHalf` tree of `both(left, right).map(...)`, leaves `void(f(state))`.
- The supervision `Set` keeps insertion order as `Set1`..`Set4`; from 5 elements it is a `HashSet` (identity-hash order). The mirror covers at most 4 inputs (model limit, stated in every property).
- Gotcha (found by the difftest, fixed): `supervision.update(_ + ((fiber, result))) *> preempt.tryGet flatMap {...}` parses as `(update *> tryGet) flatMap {...}`: an alphanumeric infix operator (`flatMap`) binds weaker than a symbolic one (`*>`). The first mirror had `update *> (tryGet flatMap {...})`; this changed the run-loop iteration count and showed only with small `IORuntimeConfig` thresholds (`runtime` field). Shrunk case: `parTraverseN(1)([1])(pure)` with thresholds 2/2.
- Method: walking the real `IO` tree with reflection (apply each closure to real or dummy arguments, print `productPrefix`) checks a mirror's term shapes directly. Script pattern: `package cats.effect` (the tracing types are package-private), `Poll` identity stub.

## Difftest

- Op `parTraverseN {n, xs, x, f}` (format v2): `IO.parTraverseN(n)(xs)(x => I(f)).map(list)`; the result list is right-nested pairs ending in unit.
- Lean decoder: the op is handled before the big `match op with` in `decodeProgIn`; one more string alternative inside it made Lean's pattern-match compiler fail ("Stuck at remaining variables").
- Fixed cases: `difftest/cases/partraverse.jsonl` (74, `gen_v2_partraverse.py`).

## Properties

- Statements on outcomes and result values only (no marker; decision 56).
- Smoke (`lake exe ptsmoke 100`): 11,200 stopped random-schedule runs, 0 violations; the wrong functions (reversed result, dropped result, no `cancelAll` on error / on cancel) break the claims in 100 / 100 / 100 / 100 runs.
- Not stated: "at most N concurrent" (needs a running-action counter, a test marker; waits for track Res's shared privacy module) and "no leaked fiber" (the `Leak` observation of track R covers only `racePair` children; a child may still run `sem.release` when the root returns, which is by design).
