# guarantee and bracket model, and CE-0005

> Sources: Cats Effect source at v3.7.1 (`IO.scala:338-371`, `:496-530`, `:967-972`, `:1826-1830`, `:2023-2064`; `kernel/.../MonadCancel.scala:344-456`; `laws/.../MonadCancelLaws.scala:28-29`); own Lean work and scala-cli runs, 2026-11-10
> Raw: [Track G notes](../../raw/cats-effect/2026-11-10-track-g-bracket-notes.md)

## Overview

Phase 6, track G. The model mirrors `IO#guarantee`, `IO#guaranteeCase`, `IO#bracket`, `IO#bracketCase`, `IO.bracketFull` and `reportError`, and the kernel defaults of `MonadCancel` with the `IO` operations as twins. The twin `IO.bracketFull` vs kernel `bracketFull` is refuted: CE-0005. Four other statements are `open` with smoke tests.

## Files

| File | Content |
|---|---|
| `Model/Bracket.lean` | Mirror (closures `BLam`, namespace 7), sources `Src`, builders, `LibEnv`, `isLib`, lemmas `libEnv_of_dispatch`, `call_congr`; fixed twin `fixedBracketFullIO` (not CE code) |
| `Model/BracketExamples.lean` | Small user environment for smoke tests |
| `Props/Phase6/Bracket.lean` | 5 properties, the parent-cancel test program, markers |
| `Proofs/Phase6/BracketFullTwin.lean` | `bracketFullIsKernelDefault_refuted` and the well-formed witness |
| `Proofs/Phase6/BracketFullFixed.lean` | Fixed-twin check (decision 39) |
| `Proofs/Phase6/BracketSmoke.lean` | Kernel-checked smoke tests: the law (14 pairs + wrong-function test), the pure-use twin (4) |
| `test/Phase6/BracketSmokeParent.lean` | `#guard` smoke tests of the two invariants (parent cancel, about 3,000 states per program; `decide +kernel` needs about 19 GB, so not in the build). Run: `lake env lean test/Phase6/BracketSmokeParent.lean` |

## Mirror rules

- `F = IO`. Each Scala lambda is a library closure (odd id). A captured `IO` is a source code: `Src.ext s` is the caller's program (`ioOf s`); other `Src` cases are terms the mirror builds.
- A user function (`finalizer`, `acquire`, `use`, `release`) is called inside the lambda body, as in Scala: `finalizer(Outcome.canceled)` runs when the `guaranteeCase` body runs. Effects come first; a throw of the user function is a throw of the lambda.
- Leaf lambdas (`_ => this`, `_ => fin`, `(a, _) => release(a)`, `release(a, _)`) run inline. So the mirror calls user code only on even ids, and an environment without recursion is a `LibEnv` (`libEnv_of_dispatch`).
- `ec.reportFailure(t)` is the user effect `UserEffect.report` (new). It logs `TraceEv.reportFailure`, which `Obs.reports` observes.
- `IO.defer(t)` = `Delay(thunk).flatMap(ev)`: the thunk returns `unit` and `ev` does the work. Same iteration, same `try` (`IOFiber.scala:420-437`).

## Twins

| Pair | Result |
|---|---|
| `IO#guarantee` vs kernel `guarantee` (= `IO#guaranteeCase(_ => fin)`) | the law `guaranteeIsGuaranteeCase`; open, smoke tests agree |
| `IO#guaranteeCase` vs kernel `guaranteeCase` | differ only in `reports`: the kernel drops a finalizer error in the error case, IO reports it. Deliberate; not registered |
| `IO.bracketFull` vs kernel `bracketFull` | refuted (CE-0005) |
| `IO#bracket`/`bracketCase` vs kernel | the kernel calls the virtual `bracketFull` = `IO.bracketFull`: same closures |

## CE-0005

`IO.bracketFull` builds `IO.defer(poll(use(a)))`: `use(a)` is called while the fiber is masked. The kernel builds `poll(unit >> use(a))`: unmask first. With a cancel request during acquire (parent cancel, or `IO.canceled` in acquire) and a `use` that throws, IO ends `Errored(e)` and release gets `Errored(e)`; the kernel ends `Canceled` and release gets `Canceled`. An effectful `use` runs only in IO. The model predicted this before the Scala run. Reproduced on 3.7.1, series/3.x, series/3.7.x. Priority low. Fix: `poll(IO.defer(use(a)))`.

## Properties

| Entry | Status | Note |
|---|---|---|
| `core.IO.bracketFull.kernelDefaultTwin` | refuted | witness: acquire `IO.canceled`, use throws |
| `core.IO.bracketFull.kernelDefaultTwin.pureUse` | open | ordinary inputs; needs a simulation proof |
| `laws.MonadCancelLaws.guaranteeIsGuaranteeCase.IO` | open | 14 smoke pairs, wrong-function test |
| `core.IO.bracket.releaseOnce` | open | parent cancels child (decision 50); markers `A` (acquire done), `R` (release starts) |
| `core.IO.guarantee.finalizerOnce` | open | same shape |

Why open: a proof for all programs needs a simulation or a state invariant over `Sched.tickP` and all of `Step.lean`. Not done.

## Difftest (format v2)

Ops `guarantee`, `bracket`, `bracketCase`, `bracketFull` ([format](../methodology/difftest-program-format.md)). Agreement: per op 51,290 to 55,575 agreeing cases over seeds 1-3 (details in the raw note). The language cannot make a throwing `use`, so CE-0005 is only in the reproducer.

## See Also

- [Kernel typeclasses model](kernel-typeclasses-model.md)
- [Resource model and CE-0002](resource-model.md)
- [Outcome sets, Eqv and the IO laws](../semantics/outcome-equivalence.md)
- [Difftest program format](../methodology/difftest-program-format.md)
- [Bug history](bug-history.md)
