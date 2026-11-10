import CatsEffectInLean.Model.IOInstance
import CatsEffectInLean.Model.WellFormed

/-!
# `MonadCancel` laws for `IO` (Phase 4 step 2)

Each law of `laws/shared/src/main/scala/cats/effect/laws/MonadCancelLaws.scala` (`L/` below) at
Cats Effect `v3.7.1`, instantiated at `IO`: `F` is the model's `IO`, each `F.x` call is the
`IO.asyncForIO` operation in `CatsEffectInLean/Model/IOInstance.lean` (`IOI.x`), and `<->` is
`Eqv` (`CatsEffectInLean/Model/Outcomes.lean`): the same observation sets over all schedules.

- The generic statement of each law is in `CatsEffectInLean/Props/Kernel/MonadCancelLaws.lean`.
  The calls and their nesting here are the same. Why this is not
  `lawX IO.ops IO.eqv`: see the module doc of `IOInstance.lean`.
- Scala's `fa : F[A]` becomes `fa : IO`, a closed model term, for all `fa`. The user
  environment `env` is universally quantified. Each Scala lambda of the law is a user function
  id; the hypothesis `IOI.Lam.*` says that `env` runs it as that lambda. Each lambda has its
  own id variable (two ids can be equal only if their lambdas agree). `env` is free on all
  other ids, so `fa` and `fin` can contain any user code.
- Both sides are `WellFormedIO` (`CatsEffectInLean/Model/WellFormed.lean`, decision 27): the
  programs and the user code are ones that Scala can write (no forged fiber, `poll` or
  `ContState` ids, user code reads only through handles it holds). This is a type invariant,
  not an assumption about the interesting case. A side is well-formed when `fa` and the user
  functions are; the law adds no other hypothesis.
- `Eqv` uses the default runtime configuration (`Config`: thresholds 512 and 1024, the
  `TestControl` and default `IORuntime` values) and the `IOFiber` mask model
  (`counterMaskModel`).
- One property per law and instance (decision 16 in
  `raw/project-decisions/2026-11-10-phase0-decisions.md`). `IO` has root cancel scope
  `Cancelable` (`IOI.rootCancelScope`), so `MonadCancelTests` checks the three
  `Cancelable`-only laws for `IO` (`MonadCancelTests.scala:138-147`), not
  `uncancelableIdentity` and `canceledUnitIdentity`.
-/

namespace CatsEffectInLean.Props.IO.MonadCancelLaws

open CatsEffectInLean.Model

/-- `<->` for `IO` in the laws below. -/
def IOEqv (env : UserEnv) (p q : IO) : Prop :=
  Eqv {} counterMaskModel env p q

/-- `L/MonadCancelLaws.scala:94-95` (root scope `Cancelable` only), at `IO`:
`F.canceled >> fa.void <-> F.canceled`.

`>>` is `F.flatMap(F.canceled)(_ => fa.void)` (`IOI.flatMap`); `fa.void` is `IOI.void fa`
(`IO.scala:961-962`, `map(_ => ())`). `k` is the lambda `_ => fa.void`. -/
def canceledAssociatesLeftOverFlatMap : Prop :=
  ∀ (env : UserEnv) (fa : IO) (k : Nat),
    IOI.Lam.constProg env k (IOI.void fa) →
    WellFormedIO env (IOI.flatMap IOI.canceled (.user k)) →
    WellFormedIO env IOI.canceled →
    IOEqv env (IOI.flatMap IOI.canceled (.user k)) IOI.canceled

/-- `L/MonadCancelLaws.scala:75-76`, at `IO`:
`F.forceR(F.canceled)(fa) <-> F.productR(F.canceled)(fa)`.

`IOI.forceR` is `IO#forceR` (`IO.scala:452-454`): `handleError(_ => ()).productR(fa)`. `h` is
its `handleError` lambda `t => IO.pure(())`, `k` its `productR` lambda `_ => fa`. `k'` is the
lambda `_ => fa` of `IOI.productR` on the right side (`IO.scala:903-904`). -/
def forceRCanceledShortCircuits : Prop :=
  ∀ (env : UserEnv) (fa : IO) (h k k' : Nat),
    IOI.Lam.constProg env h (IOI.pure .unit) →
    IOI.Lam.constProg env k fa →
    IOI.Lam.constProg env k' fa →
    WellFormedIO env (IOI.forceR IOI.canceled (.user h) (.user k)) →
    WellFormedIO env (IOI.productR IOI.canceled (.user k')) →
    IOEqv env (IOI.forceR IOI.canceled (.user h) (.user k)) (IOI.productR IOI.canceled (.user k'))

/-- `L/MonadCancelLaws.scala:61-62`, at `IO`:
`F.uncancelable(_ => F.onCancel(fa, fin)) <-> F.onCancel(F.uncancelable(_ => fa), fin)`.

`b₁` is the body `_ => F.onCancel(fa, fin)`, `b₂` the body `_ => fa`. The comment at
`L/MonadCancelLaws.scala:47-60` says that this law, together with the monad laws, is
"effectively in violation of the monad laws". The law itself is checked for `IO` by the
Cats Effect test suite. -/
def onCancelAssociatesOverUncancelableBoundary : Prop :=
  ∀ (env : UserEnv) (fa fin : IO) (b₁ b₂ : Nat),
    IOI.Lam.constProg env b₁ (IOI.onCancel fa fin) →
    IOI.Lam.constProg env b₂ fa →
    WellFormedIO env (IOI.uncancelable (.user b₁)) →
    WellFormedIO env (IOI.onCancel (IOI.uncancelable (.user b₂)) fin) →
    IOEqv env (IOI.uncancelable (.user b₁)) (IOI.onCancel (IOI.uncancelable (.user b₂)) fin)

/-- `L/MonadCancelLaws.scala:32-33`, at `IO`: `F.uncancelable(_(fa)) <-> fa`.

`b` is the body `poll => poll(fa)` (`IOI.Lam.pollApply`). -/
def uncancelablePollIsIdentity : Prop :=
  ∀ (env : UserEnv) (fa : IO) (b : Nat),
    IOI.Lam.pollApply env b fa →
    WellFormedIO env (IOI.uncancelable (.user b)) →
    WellFormedIO env fa →
    IOEqv env (IOI.uncancelable (.user b)) fa

end CatsEffectInLean.Props.IO.MonadCancelLaws
