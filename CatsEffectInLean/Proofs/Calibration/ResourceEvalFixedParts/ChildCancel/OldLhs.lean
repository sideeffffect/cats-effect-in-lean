import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedChecks

/-! One third of the CE-0002 check `old_childCancel` (`Old_childCancel.lean`), in its own file for memory. -/

namespace CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceFixed

theorem old_childCancel_lhs : exactP {} counterMaskModel (env (gFamily.getD 5 .canceled)) allocOld (exploreP {} counterMaskModel (env (gFamily.getD 5 .canceled)) bound allocOld) = true := by decide +kernel

end CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed
