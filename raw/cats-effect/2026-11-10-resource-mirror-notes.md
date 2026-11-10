# Resource mirror and CE-0002 refutation notes

> Source: own Lean work (`CatsEffectInLean/Model/ValCodec.lean`, `Model/Resource.lean`, `Model/ResourceExamples.lean`, `Props/Calibration/ResourceEval.lean`, `Proofs/Calibration/ResourceEval.lean`), Lean v4.35.0; Cats Effect source at v3.7.1 (`kernel/shared/src/main/scala/cats/effect/kernel/Resource.scala`, `core/shared/src/main/scala/cats/effect/IO.scala`); scala-cli runs of `reproducers/CE-0002/Repro.scala` on 3.7.1, `3.7.1-89-de84c01` (series/3.x) and `3.7.1-15-2f94201` (series/3.7.x)
> Collected: 2026-11-10
> Published: 2026-11-10 (own research note)

## What was mirrored

- `Resource` ADT (`Resource.scala:1167-1178`): `Allocate`, `Bind`, `Pure`, `Eval`.
- `allocatedCase` (`Resource.scala:464-531`): the `loop` with all four branches in Scala order; the `Allocate` branch (`:485-513`) with `F.uncancelable`, `rel2` (`:490`), `F.pure((b, rel2))` for `Nil`, and `poll(continue(...)).onCancel(rel(Canceled)).onError{...}` for `Frame`.
- `Resource.eval` (`:992`), `Resource.pure` (`:977`), `flatMap` (`:388`), `make` (`:900`) through `apply`/`applyCase`/`applyFull` (`:826-880`), `ExitCase` (`:1190-1232`).
- `F = IO`: `IO#onError` (`IO.scala:605-606`), `IO#handleError` (`:532-533`), `*>` = `productR` (`:138`, `:903`).

## Design: closures with captured data

- The model syntax is first-order (`Fn.user id`). `allocatedCase` builds lambdas at run time that capture a stack, a release function and a `poll`.
- Solution: each library lambda is a constructor of `Clo`. `Clo.toVal` writes it as a `Val`. `ValCodec` gives an injective `Val → Nat` code (5-bit tag, Elias-gamma numbers, sentinel bit). Closure id = `2 * code + 1` (odd). User code has even ids (`uid k = 2k`). `REnv.toEnv` dispatches by parity.
- No edit of `Syntax.lean` or `Step.lean` was needed.
- Function values (`ExitCase => F[Unit]`) and the `F[Unit]` of `make` are `Val` descriptors (`RelFn`, `ioRelease`).
- `Bind` functions, `make` acquire programs and release builders are pure Lean functions in `REnv` (no side effects). `make` calls the release builder in its `map` (to see a throw) and again when the release runs; for a pure builder this is the same `IO`.

## Model limits

- `loop` fuel 1,000,000; with no fuel left the model returns a program that never ends (no outcome).
- Ill-typed values: fatal throw, code 900001.
- Application of `rel2` (`Resource.scala:490`) is not mirrored (needs `IO#guarantee` and `reportError` with `ec.reportFailure`): fatal throw, code 900002. `allocatedCase` itself never applies `rel2`.
- Not mirrored: `fold`/`use`, `allocated`, `Resource#map`, `both`, `race`, `timeout`.

## Property and refutation

- Property `resourceEvalPreservesUncancelable`: for all `REnv` and all `g`, with `fa = IO.uncancelable(_ => g)`: `Resource.eval(fa).allocatedCase <-> IO.uncancelable(_ => Resource.eval(fa).allocatedCase)` (`Eqv`).
- Reading of "Preserves interruptibility of `fa`": an uncancelable `fa` gives an uncancelable allocation. "`x` is uncancelable" = masking `x` changes nothing.
- Witness: `g = IO.canceled`. Left: `Canceled` (fuel ≥ 7, every pick list). Right: `Succeeded(((), _ => F.unit))` at fuel 8. `fa` alone: `Succeeded(())`.
- Kernel cost: the whole proof file checks in under 1 s.

## Gotcha: `rfl` with a free fuel

- `runObs ... (f + 7) ... = some o := rfl` fails (elaborator `isDefEq` gives up) when the run calls a `Resource` closure. The same with fuel `7` and a free task limit `f + 7` works.
- Fix: lemma `runSchedState_add` (a halted run stays halted with more fuel), then `rfl` at fuel 7.

## Examples (`decide +kernel`, all pass)

| Example | Result |
|---|---|
| `make(acq)(rel).allocatedCase` | `Succeeded((42, rel2))`, release not run |
| `make.flatMap(_ => eval(raiseError))` | `Errored`, release ran |
| `make.flatMap(_ => eval(canceled))` | `Canceled`, release ran |
| two `make`, then error | releases in LIFO order |
| `applyFull` with a user release function | it gets `Errored(e)`; it is also called (not run) with `Canceled` when `onCancel(rel(Canceled))` is built (strict argument) |
| case B, `eval` / `make` twin | `Canceled`, continuation skipped / `Succeeded`, continuation ran |
| case C, `eval` / masked | `Canceled` / `Succeeded` |
| fix of PR #4630 (wrong-function test) | `Succeeded` on both sides of case C |

## Reproducer case C

Added to `reproducers/CE-0002/Repro.scala`: run `alloc` and `IO.uncancelable(_ => alloc)` as fibers, compare outcome kinds.

| Version | A | B | C | Last line |
|---|---|---|---|---|
| 3.7.1 | fail | fail | fail | REPRODUCED CE-0002 |
| 3.7.1-89-de84c01 (series/3.x) | fail | fail | fail | REPRODUCED CE-0002 |
| 3.7.1-15-2f94201 (series/3.7.x, fix) | ok | ok | ok | NOT REPRODUCED CE-0002 |
