# Resource model and CE-0002

> Sources: Cats Effect source at v3.7.1 (`Resource.scala:156-196`, `:388`, `:464-531`, `:826-993`, `:1167-1232`; `IO.scala:138`, `:532-533`, `:605-606`, `:903-904`, `:2017-2102`); `series/3.7.x` commit `2f94201` `Resource.scala:464-530` (fix PR #4630); own Lean work and scala-cli runs, 2026-11-10
> Raw: [Resource mirror notes](../../raw/cats-effect/2026-11-10-resource-mirror-notes.md); [Calibration reproducers notes](../../raw/cats-effect/2026-11-10-calibration-reproducers-notes.md); [Review 1 fixes notes](../../raw/project-decisions/2026-11-10-review1-fixes-notes.md); [Preemptive EqvP notes](../../raw/project-decisions/2026-11-10-preemptive-eqv-notes.md)

## Overview

The second refuted property of the project. `Resource.eval(fa).allocatedCase` is `fa.flatMap(...)` with no mask (`Resource.scala:526-527`). So the `flatMap` after `fa` is a cancelation point, also when `fa` is uncancelable. The Scaladoc of `Resource.eval` says "Preserves interruptibility of `fa`" (`Resource.scala:986-987`). The Lean refutation and reproducer case C show the same defect. Since review batch 2 the statement uses `EqvP` (preemption at any run-loop iteration), and a fixed twin (PR #4630) satisfies it on a family of programs (decision 39). Status of the record: draft, waits for review.

## Files

| File | Content |
|---|---|
| `Model/Codec.lean` | The one closure codec (decision 31): `Val ↔ Nat` code, roundtrip theorem `natToVal_valToNat`, id convention `libFn`/`userFn` |
| `Model/Resource.lean` | `Res` ADT, `allocatedCase` loop, `make`, closures `Clo`, release values `RelFn`, `REnv` |
| `Model/ResourceExamples.lean` | 15 checks: success, release on error, release on cancel, LIFO, `ExitCase`, cases B and C, fix of PR #4630 |
| `Props/Calibration/ResourceEval.lean` | `resourceEvalPreservesUncancelable` |
| `Proofs/Calibration/ResourceEval.lean` | `resourceEvalPreservesUncancelable_refuted` (exact `EqvP` sets) |
| `Model/ResourceFixed.lean` | Fixed twin `allocatedCaseFixed` (PR #4630), closures `FClo`, `FEnv` |
| `Proofs/Calibration/ResourceEvalFixedFamily.lean` | The 9-program domain of the fixed-twin check |
| `Proofs/Calibration/ResourceEvalFixed.lean` | `fixedTwin_holds`: the twin satisfies the equation for all 9 |
| `Proofs/Calibration/ResourceEvalFixedOld.lean` | v3.7.1 on the same domain: fails for the 3 self-cancel programs, holds for the other 6 |

## Mirror

- `F = IO`. Each `F.x` call is the `IOAsync` method and the `IO` node it builds (`IOI`, see [Outcome sets](../semantics/outcome-equivalence.md)).
- `loop` (`Resource.scala:480-528`): four branches in Scala order. `Allocate` → `F.uncancelable(allocBody)`. `Bind` → push the frame. `Pure` → `(v, release).pure` or `loop(head(v), tail, release)`. `Eval` → `fa.flatMap(evalK)`. Fuel 1,000,000; at 0 a program that never ends.
- `allocBody`/`allocK` (`:486-512`): `rel2` is built; `Nil` → `F.pure((b, rel2))`; `Frame` → `poll(continue(head(b), tail, rel2)).onCancel(rel(Canceled)).onError{...}`, in Scala evaluation order. `rel(Canceled)` is called when the `onCancel` is built (strict argument).
- `make` = `Allocate(_ => acquire.map(a => a -> release(a)).map(...))` through `apply`, `applyCase`, `applyFull` (`:826-902`).

## Closures in a first-order syntax

- A library lambda that captures data is a `Clo` constructor. Its id is `2 * valToNat c.toVal + 1` (odd). User function `k` has id `2k` (`uid k`). `REnv.toEnv` decodes odd ids and runs the mirror (`cloCall`).
- Function values (`ExitCase => F[Unit]`) and `release(a)` of `make` are `Val` descriptors (`RelFn`, `ioRelease`).
- `REnv` user code: `user` (ordinary `UserEnv`), `bind` (the `S => Resource` functions), `acquire`, `release`. `bind` and `release` are pure Lean functions (restriction: no side effects).
- No change of `Syntax.lean` or `Step.lean` was needed. `Queue` and `timeout` use the same codec (`Model/Codec.lean`; the former `ValCodec` is now the only codec, decision 31).
- `isLib id`: odd and decodes to a `Clo`. `REnv.WellFormed r p` = `WellFormed isLib [] r.toEnv p` plus: `acquire k` passes `progOK` with no handles; `release k a` and `bind k a` build only values with the handles of `a` (`Res.ok`).

## Property

`resourceEvalPreservesUncancelable`: for all `REnv`, `g`, and ids `b`, `u` with `b = _ => g` and `u = _ => alloc`, and `r.WellFormed` for both sides (type invariant, decision 27; see [Outcome sets](../semantics/outcome-equivalence.md)):

```
fa    = IO.uncancelable(_ => g)
alloc = Resource.eval(fa).allocatedCase
alloc <-> IO.uncancelable(_ => alloc)        -- EqvP {} counterMaskModel
```

Why this reads "preserves interruptibility": `fa` is uncancelable (its body ignores `poll`). Then allocating `Resource.eval(fa)` must be uncancelable too. "`x` is uncancelable" = masking `x` changes nothing. `allocatedCase` is the interpreter of `allocated`, `race` (so `timeout`), `onCancel`, `guaranteeCase`, `evalOn`, `attempt` and `Resource.uncancelable` (`Resource.scala:335`, `:552`, `:591-740`, `:1086-1089`). `EqvP` has no outside canceller (decision 22); cancelation comes from `g` itself. Only the uncancelable direction is stated.

Why `EqvP`, not `Eqv` (review batch 2): the right side has one more run-loop iteration (the outer `Uncancelable`). Under the replay `Eqv`, a child fiber of `g` then sees a different auto-yield position, so `¬P` was true for every implementation (HOLLOW). `EqvP` allows a preemption at any iteration, as the multi-threaded runtime does, so iteration counts are not observed ([Outcome sets](../semantics/outcome-equivalence.md)).

## Refutation

- Witness: `g = IO.canceled` (reproducer case C). `fa` alone: `Succeeded(())`.
- Exact outcome sets under `EqvP` (`exploreP`, closed lists, `decide +kernel`): left `{Canceled}` (26 states), right `{Succeeded(((), _ => F.unit))}` (34 states). One fiber, so preemption only splits the run.
- Wrong-function test: the fix of PR #4630 gives `Succeeded` on both sides (examples `fixed_lhs`, `fixed_rhs`). The real `series/3.7.x` snapshot with the fix agrees (case C ok).

## Fixed-twin check (decision 39)

- `allocatedCaseFixed` mirrors `series/3.7.x` `Resource.scala:464-530`: one `F uncancelable { poll => ... }` around the loop (`:470`); `Allocate` → `resource(poll) flatMap` (`:486`); `Frame` → `(poll(F.unit) >> continue(head(b), tail, rel2)).onCancel(...).onError(...)` (`:507-509`, `>>` is by name, so `continue` runs in the lambda `FClo.thenK`); `Eval` → `poll(fa).flatMap(...)` (`:525`).
- Closures: `FClo` with tags 20-23 (no overlap with `Clo` tags 0-8). `FEnv.callV` tries `FClo`, else the v3.7.1 closures. The body captures `this : Res` as an index into `FEnv.res` (a `Val` cannot hold a `Res`).
- Domain: `g` ∈ {`canceled`, `emit 1`, `raiseError`, `canceled >> emit 1`, `start(emit 9) >> emit 1`, `start(emit 9).flatMap(_.cancel)`, `start(emit 9).flatMap(_.join)`, `start(emit 9) >> canceled`, `start(emit 9) >> emit 1 >> emit 2`}. All fuel values and all schedules with preemption (exact sets, 34 to 322 states).
- Result: the twin satisfies the equation for all 9. v3.7.1 fails it exactly for the 3 programs with a self-cancel. So the statement separates the bug from the fix: not HOLLOW by the wrong-function test of batch 2.
- Not checked: the cancelable direction ("a cancelable `fa` stays cancelable"), which would catch an over-masking `Eval` (batch 2, fix 3).
- Ordinary input: the witness is an ordinary program, so no separate property is needed.
- The witness is well-formed: `alloc_wellFormed`, `rhs_wellFormed` (start program by `decide +kernel`; user code by cases on `id / 2`: it ignores the view, has no effects, and returns `IO.canceled`, `alloc` or a throw).

## Gotchas

- `rfl` on a run with a free fuel `f + 7` fails when the run calls a `Resource` closure (old `Eqv` proof). The `EqvP` proof avoids it: the closed state list covers all fuel values.
- One `decide +kernel` for many programs runs out of memory (8 GB). Use one declaration per program and side.
- A user release function with a side effect shows the strict call `rel(ExitCase.Canceled)` at build time, even when that finalizer never runs.

## Limits

- Application of `rel2` (`Resource.scala:490`) is not mirrored. `IO#guarantee` and `reportError` are mirrored since track G (`Model/Bracket.lean`, `UserEffect.report`; see [guarantee and bracket model](bracket-model.md)); batch 6.2 can use them. It gives a fatal throw with code 900002. `allocatedCase` never applies `rel2` itself.
- Ill-typed values give a fatal throw with code 900001 (impossible in Scala).
- Not mirrored here: `fold`/`use`, `allocated`, `both` and the application of `rel2` are mirrored since track Res in `Model/ResourceUse.lean` ([Resource use, allocated, both](resource-use-both-model.md)); this module is unchanged. Still not mirrored: `map`, `race`, `timeout` (case A). Inventory rows `make`, `flatMap`, `apply*` stay `todo` (mirrored, but no proven or refuted entry names them).

## See Also

- [Cats Effect bug history and target areas](bug-history.md)
- [SyncIO and syncStep model (CE-0001)](syncio-and-syncstep-model.md)
- [Outcome sets, `Eqv` and the IO laws](../semantics/outcome-equivalence.md)
- [Scheduler model](scheduler-model.md)
- [Kernel evaluation of the model](../lean/kernel-evaluation.md)
- [Registry and audit](../methodology/registry-and-audit.md)
- [guarantee and bracket model, CE-0005](bracket-model.md)
- [Resource use, allocated, both, and CE-0020](resource-use-both-model.md)
