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

* `r : REnv`: all user code (`CatsEffectInLean/Model/Resource.lean`). Hypotheses: user
  function `b` is the body `_ => g` and user function `u` is the body `_ => alloc`
  (`IOI.Lam.constProg`, the project convention for Scala lambdas), and the type invariant
  `REnv.WellFormed` for both sides (decision 27, `CatsEffectInLean/Model/WellFormed.lean`):
  the programs and the user code are ones that Scala can write. `g` is any such program.
* `alloc` is the program that `Resource.eval(fa).allocatedCase` builds (`allocatedCase` of
  `Res.evalOf fa`). For `Eval` it never throws; the equation only names the result.
* `<->` is `EqvP` (`CatsEffectInLean/Model/Outcomes.lean`): the same observations (outcome,
  emitted trace, `Ref` cells, reported errors) over all fuel values and all schedules of the
  preemptive multi-fiber scheduler (`CatsEffectInLean/Model/SchedP.lean`), default `Config`,
  `counterMaskModel` (the `IOFiber` mirror). A schedule can preempt a fiber between any two
  run-loop iterations (decisions 29 and 36), as on the multi-threaded runtime. So the two
  sides are not told apart by their iteration counts. (The outer `IO.uncancelable` of the
  right side adds one iteration. With the replay `Eqv`, that alone made the statement false
  for every implementation: review batch 2, wrong-function test.) `EqvP` has no outside
  canceller (decision 22: the program runs alone). Cancelation still comes from the program
  itself: `IO.canceled` inside `g`, or a fiber that `g` starts and that cancels a handle it
  received.
* Fixed-twin check (decision 39): the fix of upstream PR #4630, mirrored as
  `allocatedCaseFixed` (`CatsEffectInLean/Model/ResourceFixed.lean`), satisfies the same
  equation for a family of programs `g` over all schedules with preemption, and v3.7.1 does
  not (`CatsEffectInLean/Proofs/Calibration/ResourceEvalFixed.lean`).

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
    r.WellFormed alloc →
    r.WellFormed (IOI.uncancelable (uid u)) →
    EqvP {} counterMaskModel r.toEnv alloc (IOI.uncancelable (uid u))

end CatsEffectInLean.Props.Calibration
