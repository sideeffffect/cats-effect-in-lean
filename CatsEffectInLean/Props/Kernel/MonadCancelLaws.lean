import CatsEffectInLean.Kernel.MonadCancel

/-!
# `MonadCancel` laws, generic over the instance (Phase 4 step 2)

Each law of `laws/shared/src/main/scala/cats/effect/laws/MonadCancelLaws.scala` (`L/` below)
at Cats Effect `v3.7.1`, as a `Prop` over an instance `M : MonadCancelOps F E` and an
equivalence `Eqv`.

- `lhs <-> rhs` in Scala builds `IsEq(lhs, rhs)` (`L/IsEq.scala`). The test suite checks it
  with an `Eq[F[A]]`. Here `Eqv` is that relation, a parameter. For `IO`, `Eqv` will be
  "same set of outcomes over all schedules" (project plan, Phase 4 step 2).
- The calls are the same as in the Scala law: `F.x` is the field `M.x`; the syntax
  `fa >> fb` is `M.flatMap fa (fun _ => fb)` (`cats/syntax/flatMap.scala:54`); `*>` and
  `F.productR` are `M.productR`; `.attempt`, `.void`, `.map` are `M.attempt`, `M.void`,
  `M.map`.
- Scala law type parameters and arguments (`[A]`, `fa: F[A]`) become `∀`. Scala's
  `Arbitrary` generators are not a restriction here.
- These are law schemas with parameters. They are not registered. A registered property
  is a closed `Prop`, for example (later)
  `def io_guaranteeIsGuaranteeCase : Prop := guaranteeIsGuaranteeCase IO.asyncOps IO.eqv`.
  PLACEHOLDER: the `IO` instance of `MonadCancelOps` (from `CatsEffectInLean.Model`) and the
  outcome-set `Eqv` do not exist yet. Do not add a fake instance.
- `MonadCancelTests.scala:138-152` checks the last five laws only for one root scope:
  `Cancelable` (three laws) or `Uncancelable` (two laws). `lawsFor` gives the full set.
- The inherited `MonadErrorLaws` (cats) are not stated here.
-/

namespace CatsEffectInLean.Props.Kernel.MonadCancelLaws

open CatsEffectInLean.Kernel

variable {F : Type → Type} {E : Type}

/-- `L/MonadCancelLaws.scala:28-29`:
`F.guarantee(fa, fin) <-> F.guaranteeCase(fa)(_ => fin)`. -/
def guaranteeIsGuaranteeCase (M : MonadCancelOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A : Type) (fa : F A) (fin : F Unit),
    Eqv (M.guarantee fa fin) (M.guaranteeCase fa (fun _ => fin))

/-- `L/MonadCancelLaws.scala:32-33`: `F.uncancelable(_(fa)) <-> fa`. -/
def uncancelablePollIsIdentity (M : MonadCancelOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A : Type) (fa : F A),
    Eqv (M.uncancelable (fun poll => poll.apply fa)) fa

/-- `L/MonadCancelLaws.scala:35-36`:
`F.uncancelable(_ => F.uncancelable(_ => fa)) <-> F.uncancelable(_ => fa)`. -/
def uncancelableIgnoredPollEliminatesNesting (M : MonadCancelOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A : Type) (fa : F A),
    Eqv (M.uncancelable (fun _ => M.uncancelable (fun _ => fa))) (M.uncancelable (fun _ => fa))

/-- `L/MonadCancelLaws.scala:39-40`:
`F.uncancelable(op => F.uncancelable(ip => op(ip(fa)))) <-> F.uncancelable(_ => fa)`. -/
def uncancelablePollInverseNestIsUncancelable (M : MonadCancelOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A : Type) (fa : F A),
    Eqv (M.uncancelable (fun op => M.uncancelable (fun ip => op.apply (ip.apply fa))))
      (M.uncancelable (fun _ => fa))

/-- `L/MonadCancelLaws.scala:44-45`:
`F.uncancelable(_ => F.onCancel(fa, fin)) <-> F.uncancelable(_ => fa)`. -/
def uncancelableEliminatesOnCancel (M : MonadCancelOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A : Type) (fa : F A) (fin : F Unit),
    Eqv (M.uncancelable (fun _ => M.onCancel fa fin)) (M.uncancelable (fun _ => fa))

/-- `L/MonadCancelLaws.scala:61-62`:
`F.uncancelable(_ => F.onCancel(fa, fin)) <-> F.onCancel(F.uncancelable(_ => fa), fin)`.
The comment at `L/MonadCancelLaws.scala:47-60` says that this law is "effectively in
violation of the monad laws" on purpose (#1744). A refutation is not a bug by itself. -/
def onCancelAssociatesOverUncancelableBoundary (M : MonadCancelOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A : Type) (fa : F A) (fin : F Unit),
    Eqv (M.uncancelable (fun _ => M.onCancel fa fin))
      (M.onCancel (M.uncancelable (fun _ => fa)) fin)

/-- `L/MonadCancelLaws.scala:64-67`:
`F.onCancel(F.onCancel(fa, F.uncancelable(_ => fin1)), fin2) <->
F.onCancel(F.onCancel(fa, fin1), fin2)`. -/
def onCancelImpliesUncancelable (M : MonadCancelOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A : Type) (fa : F A) (fin1 fin2 : F Unit),
    Eqv (M.onCancel (M.onCancel fa (M.uncancelable (fun _ => fin1))) fin2)
      (M.onCancel (M.onCancel fa fin1) fin2)

/-- `L/MonadCancelLaws.scala:69-70`: `F.forceR(F.pure(a))(fa) <-> fa`. -/
def forceRDiscardsPure (M : MonadCancelOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A B : Type) (a : A) (fa : F B),
    Eqv (M.forceR (M.pure a) fa) fa

/-- `L/MonadCancelLaws.scala:72-73`: `F.forceR(F.raiseError(e))(fa) <-> fa`.
Scala infers `Nothing` for the type argument of `raiseError`. Here it is `Empty`. -/
def forceRDiscardsError (M : MonadCancelOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A : Type) (e : E) (fa : F A),
    Eqv (M.forceR (M.raiseError (A := Empty) e) fa) fa

/-- `L/MonadCancelLaws.scala:75-76`: `F.forceR(F.canceled)(fa) <-> F.productR(F.canceled)(fa)`. -/
def forceRCanceledShortCircuits (M : MonadCancelOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A : Type) (fa : F A),
    Eqv (M.forceR M.canceled fa) (M.productR M.canceled fa)

/-- `L/MonadCancelLaws.scala:78-79`:
`F.forceR(fa)(F.forceR(fb)(fc)) <-> F.forceR(F.forceR(fa)(fb))(fc)`. -/
def forceRAssociativity (M : MonadCancelOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A B C : Type) (fa : F A) (fb : F B) (fc : F C),
    Eqv (M.forceR fa (M.forceR fb fc)) (M.forceR (M.forceR fa fb) fc)

/-- `L/MonadCancelLaws.scala:81-82`:
`F.onCancel(F.canceled, F.uncancelable(_ => fin)) <-> F.onCancel(F.canceled, fin)`. -/
def uncancelableFinalizers (M : MonadCancelOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (fin : F Unit),
    Eqv (M.onCancel M.canceled (M.uncancelable (fun _ => fin))) (M.onCancel M.canceled fin)

/-- `L/MonadCancelLaws.scala:86-88` (root scope `Cancelable` only):
`F.onCancel(F.onCancel(F.canceled, fin1), fin2) <->
F.forceR(F.uncancelable(_ => F.forceR(fin1)(fin2)))(F.canceled)`. -/
def canceledSequencesOnCancelInOrder (M : MonadCancelOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (fin1 fin2 : F Unit),
    Eqv (M.onCancel (M.onCancel M.canceled fin1) fin2)
      (M.forceR (M.uncancelable (fun _ => M.forceR fin1 fin2)) M.canceled)

/-- `L/MonadCancelLaws.scala:90-92` (root scope `Cancelable` only):
`(F.uncancelable(_ => F.canceled >> fa).attempt >> F.unit) <->
F.forceR(F.uncancelable(_ => fa))(F.canceled)`. -/
def uncancelableCanceledAssociatesRightOverFlatMapAttempt (M : MonadCancelOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A : Type) (fa : F A),
    Eqv (M.flatMap (M.attempt (M.uncancelable (fun _ => M.flatMap M.canceled (fun _ => fa))))
          (fun _ => M.unit))
      (M.forceR (M.uncancelable (fun _ => fa)) M.canceled)

/-- `L/MonadCancelLaws.scala:94-95` (root scope `Cancelable` only):
`F.canceled >> fa.void <-> F.canceled`. Scala parses it as
`(F.canceled >> fa.void) <-> F.canceled` (same precedence, left-associative). -/
def canceledAssociatesLeftOverFlatMap (M : MonadCancelOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A : Type) (fa : F A),
    Eqv (M.flatMap M.canceled (fun _ => M.void fa)) M.canceled

/-- `L/MonadCancelLaws.scala:99-100` (root scope `Uncancelable` only):
`F.uncancelable(_ => fa) <-> fa`. -/
def uncancelableIdentity (M : MonadCancelOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  ∀ (A : Type) (fa : F A),
    Eqv (M.uncancelable (fun _ => fa)) fa

/-- `L/MonadCancelLaws.scala:102-103` (root scope `Uncancelable` only):
`F.canceled <-> F.unit`. -/
def canceledUnitIdentity (M : MonadCancelOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  Eqv M.canceled M.unit

/-- The laws that `MonadCancelTests` checks for `M`
(`laws/shared/src/main/scala/cats/effect/laws/MonadCancelTests.scala:120-152`): twelve laws
for each instance, then three more for root scope `Cancelable` or two more for
`Uncancelable`. -/
def lawsFor (M : MonadCancelOps F E) (Eqv : ∀ {A : Type}, F A → F A → Prop) : Prop :=
  guaranteeIsGuaranteeCase M Eqv ∧
  uncancelablePollIsIdentity M Eqv ∧
  uncancelableIgnoredPollEliminatesNesting M Eqv ∧
  uncancelablePollInverseNestIsUncancelable M Eqv ∧
  uncancelableEliminatesOnCancel M Eqv ∧
  onCancelAssociatesOverUncancelableBoundary M Eqv ∧
  onCancelImpliesUncancelable M Eqv ∧
  forceRDiscardsPure M Eqv ∧
  forceRDiscardsError M Eqv ∧
  forceRCanceledShortCircuits M Eqv ∧
  forceRAssociativity M Eqv ∧
  uncancelableFinalizers M Eqv ∧
  (match M.rootCancelScope with
   | .cancelable =>
     canceledSequencesOnCancelInOrder M Eqv ∧
     uncancelableCanceledAssociatesRightOverFlatMapAttempt M Eqv ∧
     canceledAssociatesLeftOverFlatMap M Eqv
   | .uncancelable =>
     uncancelableIdentity M Eqv ∧
     canceledUnitIdentity M Eqv)

end CatsEffectInLean.Props.Kernel.MonadCancelLaws
