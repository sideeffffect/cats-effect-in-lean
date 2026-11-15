import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedChecks

/-! One third of the CE-0002 check `fixed_childCancel` (`Fixed_childCancel.lean`), in its own file for memory. -/

namespace CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceFixed

theorem fixed_childCancel_rhs : exactP {} counterMaskModel (env (gFamily.getD 5 .canceled)) (.uncancelable (uid 1)) (exploreP {} counterMaskModel (env (gFamily.getD 5 .canceled)) bound (.uncancelable (uid 1))) = true := by decide +kernel

end CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed
