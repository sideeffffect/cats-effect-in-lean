# memoize model and CE-0030

> Sources: Cats Effect v3.7.1 (`IO.scala:944-945`, `:1822-1824`, `:1996-2180`; `kernel/.../GenConcurrent.scala:33-112`; `Ref.scala:140-141`, `:314`; `jvm-native/.../SyncRef.scala`; `Outcome.scala:73-74`; `Resource.scala:792-803`, `:1479-1480`; `tests/.../MemoizeSuite.scala`); git history of `GenConcurrent.scala`; own Lean and scala-cli runs, 2026-11-10
> Raw: [Track M notes](../../raw/cats-effect/2026-11-10-memoize-track-m-notes.md)

## Overview

Phase 6, batch 6.2, track M. Mirror of `IO#memoize`, difftest ops `memoize`/`memoGet` (format v2), three registered properties. One is refuted: CE-0030, a `get` that hangs forever and cannot be canceled. Two are `open` with smoke tests.

## Dispatch: no twin

`IO#memoize` = `Concurrent[IO].memoize(this)` = the kernel default `GenConcurrent#memoize` with `IOAsync`. `IOAsync` does not override it. So there is no IO-vs-kernel twin. `Resource` overrides `memoize` with another body (`memoizedAcquire`); track Res owns it.

## Files

| File | Content |
|---|---|
| `Model/Memoize.lean` | `MLam` (22 closures, namespace 30), effect codes `Eff` (namespace 31), state encoding `St`, `memoizeIO`, `getIO`, `call`; variant 1 = fixed twin (not CE code) |
| `Props/Phase6/Memoize.lean` | test programs `twoGets`, `countedTwoGets` (closures namespace 32), `env`, `run`, 3 properties |
| `Proofs/Phase6/MemoizeStuck.lean` | `memoizeNoStuckGet_refuted`, well-formed witness, `fixed_wit` |
| `Proofs/Phase6/MemoizeFixed.lean` | fixed-twin check over 120 one-preemption schedules (`lean_lib TwinChecks`, about 2 min) |
| `test/Phase6/MemoizeSmoke.lean` | `#guard` smoke and wrong-function tests (about 3 min) |
| `reproducers/CE-0030/Repro.scala` | TestControl reproducer with a fixed twin |
| `spikes/memoize/` | first TestControl spike; default-runtime spike |

## Mirror rules

- The memo state is a `Ref` cell: `Unevaluated` = `none`, `Evaluating(d, n)` = `pair (deferred d) (nat n)`, `Finished(Left e)` = `left (err e)`, `Finished(Right(IO.pure a))` = `right (some a)`, `Finished(Right(canceled *> never))` = `right none`.
- `SyncRef.get`/`update`/`modify` are one `Delay` thunk each; the `modify` function runs inside the thunk, so `fiber.get` (a `Deferred` read) and the `IO` values that it builds use the view of that step.
- A `Val` cannot hold an `IO`. The `F[B]` result of `modify` and the `IO` inside `Right` are effect codes (`Eff`); `flattenK` (the `fa => fa` of `flatten`) builds the `IO` (`effIO`). Same iteration count as Scala.
- `go` uses `IO#guaranteeCase`; its three closures are mirrored again (`gcBody`, `gcOnError`, `gcTap`), because the finalizer is a library closure. The leaves (`reportError`, `raiseK`, `asK`) are the `Bracket` closures; `never` is `Timeout.neverIO`.
- The `get` is a value: `Eff.get r src variant` (`getVal`).

## CE-0030

When `fa` cancels itself, the memo becomes `Finished(Right(canceled *> never))`. A `get` that sees `Finished` in `state.get` (line 108) runs it unmasked and ends `Canceled`. A `get` that saw `Unevaluated`/`Evaluating` there and then sees `Finished` in `state.flatModifyFull` (lines 91-92) runs it inside the `uncancelable` of `flatModifyFull`, without `poll`. `canceled` does nothing; `never` waits forever; `cancel` of that fiber waits forever. Since v3.4.5 (PR #3351); before, this path was `poll(get)`.

- Lean witness: `fa = IO.canceled`, two `get` fibers, one preemption after 35 micro-steps (also 36, 37): blocked with a `Finished` memo (`decide +kernel`).
- Scala: TestControl with thresholds (1,2), (1,4), (2,4): 50, 53, 38 of 200 seeds hang; default thresholds 0 of 200. Default multi-threaded runtime: 2,098 of 100,000 runs. Same on `series/3.x` and `series/3.7.x`.
- Fix: `finished -> poll(fromEither(result).flatten)`. Fixed twin (variant 1): never blocked in Lean (120 one-preemption schedules, 9 × 400 random schedules) and in Scala (0 of 800).
- Priority medium: needs a self-canceling `fa`, but then about 2 % of concurrent `get`s hang on a real runtime.

## Properties

| Entry | Status | Statement |
|---|---|---|
| `core.IO.memoize.noStuckGet` | refuted (CE-0030) | `twoGets`: a blocked run never has a `Finished` memo |
| `core.IO.memoize.getsAgree` | open | `twoGets`: if the root completes with `(oa, ob)`, `oa = ob` |
| `core.IO.memoize.atMostOnce` | open | `countedTwoGets` (no cancel): the counter in front of `fa` is at most 1 in every state |

- All `WellFormed` `fa`, all user code, all `PChoice` schedules (decisions 27, 29, 36). Test-program closures are library-side (odd ids): user code cannot reach the counter.
- Smoke (9 `fa` × 400 random schedules): stuck runs only for self-canceling `fa` (9, 5, 6) and none for the fixed twin; `getsAgree` 0 violations; counter max 1. Wrong function (a `get` that is `fa`): `getsAgree` fails for `fa = IO.ref(0)`, counter 2.
- Why open: a proof for all `fa` needs a state invariant over `SchedP` (memo cell, `Deferred` cell, `go` fiber outcome, subscriber count). Not done.
- Not stated: "cancel of one waiting `get` does not cancel the evaluation for the others" (MemoizeSuite tests it; difftest shape `cancelOne` covers it). A candidate for later.

## Difftest

Ops `memoize`, `memoGet` ([format](../methodology/difftest-program-format.md)). Fixed cases `memoize.jsonl`: 150 agree, 3 of them `blocked` in both runners (CE-0030 in replay). Generated: see the counts below. The mirror makes model `Deferred` cells, so the replay glue now renumbers `Deferred` handles (`deferredH`) and memo handles (`memoH`).

Depth run (`opcount.py`, seeds 1-3, 36,000 cases each, `tpl_memo` boosted): RESULT_PLACEHOLDER

## See Also

- [guarantee and bracket model](bracket-model.md)
- [race, both and fiber leaks](race-both-model.md)
- [Scheduler model](scheduler-model.md)
- [Bug history](bug-history.md)
- [Outcome sets, Eqv and the IO laws](../semantics/outcome-equivalence.md)
- [Difftest program format](../methodology/difftest-program-format.md)
