import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedChecks

/-! One third of the CE-0002 check `old_childCancel` (`Old_childCancel.lean`), in its own file for memory. -/

namespace CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceFixed

theorem old_childCancel_rhs : exactP {} counterMaskModel (env (gFamily.getD 5 .canceled)) (.uncancelable (uid 2)) (exploreP {} counterMaskModel (env (gFamily.getD 5 .canceled)) bound (.uncancelable (uid 2))) = true := by decide +kernel

end CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed
