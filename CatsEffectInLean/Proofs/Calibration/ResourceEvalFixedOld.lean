import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.Old_canceled
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.Old_emit
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.Old_error
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.Old_canceledThenEmit
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.Old_childEmit
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.Old_childCancel
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.Old_childJoin
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.Old_childCanceled
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.Old_childEmitEmit

/-!
# Fixed-twin check of CE-0002: v3.7.1 on the same domain

The domain and the method: `ResourceEvalFixedFamily.lean`. One `decide +kernel` per program
`g` of `gFamily`. v3.7.1 fails the equation (`checkNotEqvP`: both outcome sets exact and
different) for the three programs with a self-cancel, and satisfies it (`checkEqvP`) for the
other six. So, on this domain, the statement fails exactly where the bug is.
-/

namespace CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource

/-- v3.7.1 fails the equation for `g = IO.canceled` (the CE-0002 witness). -/
theorem v371_fails :
    ¬ EqvP {} counterMaskModel (env .canceled) allocOld (.uncancelable (uid 2)) :=
  not_eqvP_of_checkNotEqvP {} counterMaskModel (env .canceled) old_canceled

/-- v3.7.1 also fails it for `IO.canceled >> emit 1` and `start(emit 9) >> IO.canceled`. -/
theorem v371_fails_more :
    ¬ EqvP {} counterMaskModel (env (gFamily.getD 3 .canceled)) allocOld (.uncancelable (uid 2)) ∧
    ¬ EqvP {} counterMaskModel (env (gFamily.getD 7 .canceled)) allocOld (.uncancelable (uid 2)) :=
  ⟨not_eqvP_of_checkNotEqvP {} counterMaskModel _ old_canceledThenEmit,
   not_eqvP_of_checkNotEqvP {} counterMaskModel _ old_childCanceled⟩

end CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed
