import CatsEffectInLean.Model.Resource

/-!
# `Resource.eval` preserves interruptibility (CE-0002)

The Scaladoc of `Resource.eval`
(`kernel/shared/src/main/scala/cats/effect/kernel/Resource.scala:985-993` at `v3.7.1`):

> Lifts an applicative into a resource. The resource has a no-op release. Preserves
> interruptibility of `fa`.

## What "preserves interruptibility" means here

`fa` is uncancelable when no cancelation can stop it: `fa = IO.uncancelable(_ => g)` for any
program `g` (the body ignores its `poll`). Then the resource `Resource.eval(fa)` must also be
uncancelable when it is allocated. "Allocate the resource" is `allocatedCase`
(`Resource.scala:464-531`), the interpreter that `allocated`, `race` (so `timeout`),
`onCancel`, `guaranteeCase`, `evalOn`, `attempt` and `Resource.uncancelable` use
(`Resource.scala:335`, `:552`, `:591`, `:597`, `:706`, `:740`, `:1086-1089`). "`x` is uncancelable" is
`x <-> IO.uncancelable(_ => x)`: masking `x` changes nothing.

The direction "a cancelable `fa` stays cancelable" is not stated. The statement is the
uncancelable case only, which is the case of the Scaladoc sentence and of upstream issue
typelevel/cats-effect#4627.

## Statement

* `r : REnv`: all user code (`CatsEffectInLean/Model/Resource.lean`). No hypothesis except
  that user function `b` is the body `_ => g` and user function `u` is the body `_ => alloc`
  (`IOI.Lam.constProg`, the project convention for Scala lambdas). `g` is any program.
* `alloc` is the program that `Resource.eval(fa).allocatedCase` builds (`allocatedCase` of
  `Res.evalOf fa`). For `Eval` it never throws; the equation only names the result.
* `<->` is `Eqv` (`CatsEffectInLean/Model/Outcomes.lean`): the same observations (outcome,
  emitted trace, `Ref` cells, reported errors) over all fuel values and all pick schedules of
  the multi-fiber scheduler, default `Config`, `counterMaskModel` (the `IOFiber` mirror).
  `Eqv` has no outside canceller (decision 22: the program runs alone). Cancelation still
  comes from the program itself: `IO.canceled` inside `g`, or a fiber that `g` starts and
  that cancels a handle it received.

The counterexample (`Proofs/Calibration/ResourceEval.lean`) uses no forged handle: `g` is
`IO.canceled`.
-/

namespace CatsEffectInLean.Props.Calibration

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource

/-- `Resource.eval(fa)` (`Resource.scala:992-993`) with `fa = IO.uncancelable(_ => g)` is
uncancelable when it is allocated: `Resource.eval(fa).allocatedCase <->
IO.uncancelable(_ => Resource.eval(fa).allocatedCase)`. -/
def resourceEvalPreservesUncancelable : Prop :=
  ∀ (r : REnv) (b u : Nat) (g alloc : IO),
    IOI.Lam.constProg r.user b g →
    allocatedCase r (Res.evalOf (IOI.uncancelable (uid b))) = .ok alloc →
    IOI.Lam.constProg r.user u alloc →
    Eqv {} counterMaskModel r.toEnv alloc (IOI.uncancelable (uid u))

end CatsEffectInLean.Props.Calibration
