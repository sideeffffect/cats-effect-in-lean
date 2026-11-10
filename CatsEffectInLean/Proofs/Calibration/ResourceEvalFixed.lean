import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedFamily

/-!
# Fixed-twin check of CE-0002: the fixed twin satisfies the equation

The domain and the method: `ResourceEvalFixedFamily.lean`. One `decide +kernel` per program
`g` of `gFamily`; each proves `checkEqvP` (both outcome sets exact and equal).
-/

namespace CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceFixed

/-- The fixed-twin check for one `g`. -/
abbrev fixedCheck (g : IO) : Bool :=
  checkEqvP {} counterMaskModel (env g) bound (allocatedCaseFixed 0) (.uncancelable (uid 1))

theorem fixed_canceled : fixedCheck (gFamily.getD 0 .canceled) = true := by decide +kernel

theorem fixed_emit : fixedCheck (gFamily.getD 1 .canceled) = true := by decide +kernel

theorem fixed_error : fixedCheck (gFamily.getD 2 .canceled) = true := by decide +kernel

theorem fixed_canceledThenEmit : fixedCheck (gFamily.getD 3 .canceled) = true := by decide +kernel

theorem fixed_childEmit : fixedCheck (gFamily.getD 4 .canceled) = true := by decide +kernel

theorem fixed_childCancel : fixedCheck (gFamily.getD 5 .canceled) = true := by decide +kernel

theorem fixed_childJoin : fixedCheck (gFamily.getD 6 .canceled) = true := by decide +kernel

theorem fixed_childCanceled : fixedCheck (gFamily.getD 7 .canceled) = true := by decide +kernel

theorem fixed_childEmitEmit : fixedCheck (gFamily.getD 8 .canceled) = true := by decide +kernel

/-- The fixed twin of PR #4630 satisfies the CE-0002 equation for every `g` of the family:
`allocatedCaseFixed <-> IO.uncancelable(_ => allocatedCaseFixed)` under `EqvP`. -/
theorem fixedTwin_holds : ∀ g ∈ gFamily,
    EqvP {} counterMaskModel (env g) (allocatedCaseFixed 0) (.uncancelable (uid 1)) := by
  intro g hg
  apply eqvP_of_checkEqvP {} counterMaskModel (env g) (bound := bound)
  simp only [gFamily, List.mem_cons, List.not_mem_nil, or_false] at hg
  rcases hg with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  · exact fixed_canceled
  · exact fixed_emit
  · exact fixed_error
  · exact fixed_canceledThenEmit
  · exact fixed_childEmit
  · exact fixed_childCancel
  · exact fixed_childJoin
  · exact fixed_childCanceled
  · exact fixed_childEmitEmit

end CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed
