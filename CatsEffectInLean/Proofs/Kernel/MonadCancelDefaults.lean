import CatsEffectInLean.Props.Kernel.MonadCancelLaws

/-!
# Laws that follow from the kernel default bodies alone

Generic lemmas, not registered properties. They say which `MonadCancel` laws hold for
*every* instance that keeps a given default body (or the `MonadCancel.Uncancelable`
mixin), for every reflexive `Eqv`. So for such an instance these laws test nothing about
the instance; they matter only for an instance that overrides the method (for `IO`:
`guarantee`, `guaranteeCase`, `bracketFull`, see `wiki/cats-effect/kernel-typeclasses-model.md`).

Wrong-function test: each lemma needs its default-body hypothesis. A `guarantee` that
ignores `fin`, or an `onCancel` that always runs `fin`, breaks the hypothesis.
-/

namespace CatsEffectInLean.Proofs.Kernel.MonadCancelDefaults

open CatsEffectInLean.Kernel
open CatsEffectInLean.Props.Kernel

variable {F : Type → Type} {E : Type}

/-- If `M` keeps the default `guarantee` (`K/MonadCancel.scala:344-345`), the law
`guaranteeIsGuaranteeCase` holds for each reflexive `Eqv`. -/
theorem guaranteeIsGuaranteeCase_of_default (M : MonadCancelOps F E)
    (Eqv : ∀ {A : Type}, F A → F A → Prop) (hrefl : ∀ {A : Type} (x : F A), Eqv x x)
    (hg : ∀ {A : Type} (fa : F A) (fin : F Unit),
      M.guarantee fa fin = MonadCancel.Default.guarantee M fa fin) :
    MonadCancelLaws.guaranteeIsGuaranteeCase M Eqv := by
  intro A fa fin
  rw [hg]
  exact hrefl _

section Uncancelable

variable (M : MonadCancelOps F E) (Eqv : ∀ {A : Type}, F A → F A → Prop)
  (hrefl : ∀ {A : Type} (x : F A), Eqv x x) (hM : M.IsUncancelableMixin)
include hrefl hM

/-- `MonadCancel.Uncancelable` (`K/MonadCancel.scala:593-610`) satisfies
`uncancelablePollIsIdentity`. -/
theorem uncancelablePollIsIdentity_of_mixin :
    MonadCancelLaws.uncancelablePollIsIdentity M Eqv := by
  intro A fa
  rw [hM.uncancelable]
  exact hrefl _

theorem uncancelableIgnoredPollEliminatesNesting_of_mixin :
    MonadCancelLaws.uncancelableIgnoredPollEliminatesNesting M Eqv := by
  intro A fa
  rw [hM.uncancelable, hM.uncancelable]
  exact hrefl _

theorem uncancelablePollInverseNestIsUncancelable_of_mixin :
    MonadCancelLaws.uncancelablePollInverseNestIsUncancelable M Eqv := by
  intro A fa
  simp only [hM.uncancelable]
  exact hrefl _

theorem uncancelableEliminatesOnCancel_of_mixin :
    MonadCancelLaws.uncancelableEliminatesOnCancel M Eqv := by
  intro A fa fin
  simp only [hM.uncancelable, hM.onCancel]
  exact hrefl _

theorem onCancelAssociatesOverUncancelableBoundary_of_mixin :
    MonadCancelLaws.onCancelAssociatesOverUncancelableBoundary M Eqv := by
  intro A fa fin
  simp only [hM.uncancelable, hM.onCancel]
  exact hrefl _

theorem onCancelImpliesUncancelable_of_mixin :
    MonadCancelLaws.onCancelImpliesUncancelable M Eqv := by
  intro A fa fin1 fin2
  simp only [hM.onCancel]
  exact hrefl _

theorem uncancelableFinalizers_of_mixin :
    MonadCancelLaws.uncancelableFinalizers M Eqv := by
  intro fin
  simp only [hM.onCancel]
  exact hrefl _

theorem uncancelableIdentity_of_mixin :
    MonadCancelLaws.uncancelableIdentity M Eqv := by
  intro A fa
  rw [hM.uncancelable]
  exact hrefl _

theorem canceledUnitIdentity_of_mixin :
    MonadCancelLaws.canceledUnitIdentity M Eqv := by
  unfold MonadCancelLaws.canceledUnitIdentity
  rw [hM.canceled]
  exact hrefl _

end Uncancelable

end CatsEffectInLean.Proofs.Kernel.MonadCancelDefaults
