# Difftest, Lean side: decoder, translation and `cediff` skeleton (own note)

> Source: own work in this repository (`tools/Difftest/`, Phase 3 step 4 preparation), built with Lean v4.35.0 on 2026-11-10; Scala sources read at Cats Effect v3.7.1 (`IO.scala`, `IOFiber.scala`, `IODeferred.scala`, `kernel/jvm-native/.../SyncRef.scala`, `kernel/.../Async.scala`)
> Collected: 2026-11-10
> Published: 2026-11-10

## What was built

- `lean_lib Difftest` (`srcDir := "tools"`) and `lean_exe cediff`. They are not in the `CatsEffectInLean` library, so the model library does not import `Lean.Data.Json`.
- `Difftest.Prog`: AST and strict JSON decoder, same rules as `difftest/.../Json.scala`. Names become de Bruijn indices. `seq` becomes left-nested binary `seq` (`seq [p]` = `p`). `async` with and without `fin` are two constructors.
- `Difftest.Closure`: a closure is `⟨node, lam, vals⟩` (pre-order node number, lambda kind, captured values). `Clo.encode` packs it into the `Nat` of `Fn.user`. Packing: `Val` → prefix-coded token list → base-3 digits (bits as 1/2, separator 0) under a sentinel 1. Uses only `Nat` add/mul/div/mod/log2.
- `Difftest.Translate`: `tr p node env` builds the same `IO` constructor nesting as `Interp.run` in Scala. `guaranteeCase` expands as `IO.scala:523-530` (`uncancelable`, `poll(this).onCancel(fin(canceled))`, `onError` = `handleErrorWith(… *> raiseError)` at `IO.scala:605-606`, `reportError` at `IO.scala:967-971`, `flatTap` at `IO.scala:474`). `IO.never` = `async(_ => pure(Some(unit)))` (`kernel/.../Async.scala:168`, `IO.scala:2198`) = `IOCont`. `IO.async` body at `IO.scala:1418-1431`. `Ref` ops are `Delay` (`SyncRef.scala:30-94`).
- `Difftest.Env`: `denv p` runs each closure (trace events and `reportFailure` calls on the side); `userEnv p : Model.UserEnv` drops them.
- `Difftest.Tests`: 52 `#guard` checks (closure id round trip, decoder rejections, exact terms for bind, delay, handleErrorWith, guaranteeCase, onCancel, never, async, refModify, racePair).
- `lake exe cediff [FILE…]`: one JSON line per case with `size` (root term) and `unsupported` ops; `outcome` is always `unsupported` until the step function exists. Exit 1 if a case is rejected.
- Result on `difftest/cases/basic.jsonl`: 27 cases, 27 accepted, 20 without unsupported ops.

## What the Model lacks (found while translating)

1. **Closures.** `Fn.user (id : Nat)` has no captured values. Workaround: the id encodes them (above). A cleaner model type would be `Fn.user (id : Nat) (env : List Val)`.
2. **Trace output.** `UserEffect` has no "emit an observable event" case. `denv` keeps the trace on the side, so the runner can only get it if the step function also logs user calls (or the model adds `UserEffect.emit (e : Val)`). The same holds for `reportFailure` calls (`IO.scala:970`).
3. **Construction-time reads of runtime state.** `fib.join` and `fib.cancel` read the `IOFiber` fields `_join`/`_cancel` when the term is built (`IOFiber.scala:142-205`). They become `IO.pure(outcome)`/`IO.unit` after the fiber completes. `deferred.get` reads the `IODeferred` cell when the term is built (`IODeferred.scala:71`). `UserEnv.call` sees only the `Ref` snapshot, so the translation cannot choose the right term. Ops `join`, `cancel`, `deferredGet` are reported as unsupported.
4. **Allocation.** `IO.ref(a) = IO(Ref.unsafe(a))` (`IO.scala:1822`) and `IO.deferred = IO(new IODeferred)` (`IO.scala:1824`) allocate a cell in a `Delay` thunk. `UserEffect` cannot allocate. Ops `refNew`, `deferredNew` are unsupported. `deferredComplete` also needs the `IODeferred` mirror (Phase 2 step 9).
5. **`IO` values inside values.** The `async` registration returns `Option[IO[Unit]]` (`IO.scala:1418`); `Val` cannot hold an `IO`. Workaround: the thunk returns `some unit`/`none` as a marker and the next closure (`asyncSel`) rebuilds the finalizer term. The term shape is unchanged.

## Non-obvious decisions

- Error codes: `Err.code = c + 2` for `UserError(c)`; 0 = `TypeError`; 1 = harness error (unsupported op reached inside a closure).
- Scala builds `onCancel.fin` and `guaranteeCase.e` eagerly; the model rebuilds them inside closures. Building is pure for all supported ops, so the terms are equal. `tr` also builds them eagerly once, so a `TypeError` occurs at the same point.
- Async ids and fiber handles: trace events hold the `ContState` id, and an internal `handle` event marks Scala's `h.fiberHandle` calls. The runner must renumber both by first appearance to get Scala's numbering.
- `partial def` is used only in the JSON decoder (recursion through `Json` arrays) and the stdin loop. `scripts/check_forbidden.py` does not forbid it, and AGENTS.md forbids it only for model logic.

## CI

- New job `difftest`: `actions/setup-java@77dd5b2c… # v6.2.0` (temurin 21, `cache: sbt`), `sbt/setup-sbt@67d461eb… # v1.5.14`, `cd difftest && sbt -batch test`. Locally the tests take about 8 s with a warm cache.
- New step in the `lean` job: `lake build --wfail Difftest cediff`, then `lake exe cediff difftest/cases/basic.jsonl` (fails on any rejected case).
