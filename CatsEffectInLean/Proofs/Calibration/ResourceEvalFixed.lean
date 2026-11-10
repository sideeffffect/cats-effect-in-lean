import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.Fixed_canceled
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.Fixed_emit
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.Fixed_error
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.Fixed_canceledThenEmit
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.Fixed_childEmit
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.Fixed_childCancel
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.Fixed_childJoin
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.Fixed_childCanceled
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.Fixed_childEmitEmit

/-!
# Fixed-twin check of CE-0002: the fixed twin satisfies the equation

The domain and the method: `ResourceEvalFixedFamily.lean`. One `decide +kernel` per program
`g` of `gFamily`; each proves `checkEqvP` (both outcome sets exact and equal).
-/

namespace CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceFixed

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
