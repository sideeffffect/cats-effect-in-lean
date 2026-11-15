import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.ChildCancel.FixedLhs
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.ChildCancel.FixedRhs
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.ChildCancel.FixedObs

/-! The CE-0002 check `fixed_childCancel` (`ResourceEvalFixedChecks.lean`), from its three parts (each in its
own file for memory: the exact outcome set of each side, and the comparison of the two sets). -/

namespace CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceFixed

theorem fixed_childCancel : fixedCheck (gFamily.getD 5 .canceled) = true := by
  have h1 := fixed_childCancel_lhs
  have h2 := fixed_childCancel_rhs
  have h3 := fixed_childCancel_obs
  simp only [fixedCheck, checkEqvP]
  rw [h1, h2, Bool.true_and, Bool.true_and]
  exact h3

end CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed
