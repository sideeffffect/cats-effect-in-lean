import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.ChildCancel.OldLhs
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.ChildCancel.OldRhs
import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedParts.ChildCancel.OldObs

/-! The CE-0002 check `old_childCancel` (`ResourceEvalFixedChecks.lean`), from its three parts (each in its
own file for memory: the exact outcome set of each side, and the comparison of the two sets). -/

namespace CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceFixed

theorem old_childCancel : oldHolds (gFamily.getD 5 .canceled) = true := by
  have h1 := old_childCancel_lhs
  have h2 := old_childCancel_rhs
  have h3 := old_childCancel_obs
  simp only [oldHolds, checkEqvP]
  rw [h1, h2, Bool.true_and, Bool.true_and]
  exact h3

end CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed
