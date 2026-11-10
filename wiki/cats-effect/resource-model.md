# Resource model and CE-0002

> Sources: Cats Effect source at v3.7.1 (`Resource.scala:156-196`, `:388`, `:464-531`, `:826-993`, `:1167-1232`; `IO.scala:138`, `:532-533`, `:605-606`, `:903-904`, `:2017-2102`); own Lean work and scala-cli runs, 2026-11-10
> Raw: [Resource mirror notes](../../raw/cats-effect/2026-11-10-resource-mirror-notes.md); [Calibration reproducers notes](../../raw/cats-effect/2026-11-10-calibration-reproducers-notes.md); [Review 1 fixes notes](../../raw/project-decisions/2026-11-10-review1-fixes-notes.md)

## Overview

The second refuted property of the project. `Resource.eval(fa).allocatedCase` is `fa.flatMap(...)` with no mask (`Resource.scala:526-527`). So the `flatMap` after `fa` is a cancelation point, also when `fa` is uncancelable. The Scaladoc of `Resource.eval` says "Preserves interruptibility of `fa`" (`Resource.scala:986-987`). The Lean refutation and reproducer case C show the same defect. Status of the record: draft, waits for review.

## Files

| File | Content |
|---|---|
| `Model/Codec.lean` | The one closure codec (decision 31): `Val ↔ Nat` code, roundtrip theorem `natToVal_valToNat`, id convention `libFn`/`userFn` |
| `Model/Resource.lean` | `Res` ADT, `allocatedCase` loop, `make`, closures `Clo`, release values `RelFn`, `REnv` |
| `Model/ResourceExamples.lean` | 15 checks: success, release on error, release on cancel, LIFO, `ExitCase`, cases B and C, fix of PR #4630 |
| `Props/Calibration/ResourceEval.lean` | `resourceEvalPreservesUncancelable` |
| `Proofs/Calibration/ResourceEval.lean` | `resourceEvalPreservesUncancelable_refuted` |

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
alloc <-> IO.uncancelable(_ => alloc)        -- Eqv {} counterMaskModel
```

Why this reads "preserves interruptibility": `fa` is uncancelable (its body ignores `poll`). Then allocating `Resource.eval(fa)` must be uncancelable too. "`x` is uncancelable" = masking `x` changes nothing. `allocatedCase` is the interpreter of `allocated`, `race` (so `timeout`), `onCancel`, `guaranteeCase`, `evalOn`, `attempt` and `Resource.uncancelable` (`Resource.scala:335`, `:552`, `:591-740`, `:1086-1089`). `Eqv` has no outside canceller (decision 22); cancelation comes from `g` itself. Only the uncancelable direction is stated.

## Refutation

- Witness: `g = IO.canceled` (reproducer case C). `fa` alone: `Succeeded(())`.
- Left: `Canceled`, empty trace, for every fuel ≥ 7 and every pick list (single fiber; `runs_of_nil_pick` from the `IO` law proofs).
- Right: `Succeeded(((), _ => F.unit))` at fuel 8.
- Wrong-function test: the fix of PR #4630 gives `Succeeded` on both sides (examples `fixed_lhs`, `fixed_rhs`). The real `series/3.7.x` snapshot with the fix agrees (case C ok).
- Ordinary input: the witness is an ordinary program, so no separate property is needed.
- The witness is well-formed: `alloc_wellFormed`, `rhs_wellFormed` (start program by `decide +kernel`; user code by cases on `id / 2`: it ignores the view, has no effects, and returns `IO.canceled`, `alloc` or a throw).

## Gotchas

- `rfl` on a run with a free fuel `f + 7` fails when the run calls a `Resource` closure. With fuel `7` (and a free task limit) it works. Lemma `runSchedState_add` (a halted run stays halted) bridges the two.
- A user release function with a side effect shows the strict call `rel(ExitCase.Canceled)` at build time, even when that finalizer never runs.

## Limits

- Application of `rel2` (`Resource.scala:490`) is not mirrored: it needs `IO#guarantee` and `reportError` (`ec.reportFailure`). It gives a fatal throw with code 900002. `allocatedCase` never applies `rel2` itself.
- Ill-typed values give a fatal throw with code 900001 (impossible in Scala).
- Not mirrored: `fold`/`use`, `allocated`, `map`, `both`, `race`, `timeout` (case A). Inventory rows `make`, `flatMap`, `apply*` stay `todo` (mirrored, but no registered property names them).

## See Also

- [Cats Effect bug history and target areas](bug-history.md)
- [SyncIO and syncStep model (CE-0001)](syncio-and-syncstep-model.md)
- [Outcome sets, `Eqv` and the IO laws](../semantics/outcome-equivalence.md)
- [Scheduler model](scheduler-model.md)
- [Kernel evaluation of the model](../lean/kernel-evaluation.md)
- [Registry and audit](../methodology/registry-and-audit.md)
