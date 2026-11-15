import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedChecks

/-! One third of the CE-0002 check `fixed_childCancel` (`Fixed_childCancel.lean`), in its own file for memory. -/

namespace CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceFixed

theorem fixed_childCancel_obs :
    ((obsList (exploreP {} counterMaskModel (env (gFamily.getD 5 .canceled)) bound (allocatedCaseFixed 0))).all (fun o => (obsList (exploreP {} counterMaskModel (env (gFamily.getD 5 .canceled)) bound (.uncancelable (uid 1)))).contains o) &&
      (obsList (exploreP {} counterMaskModel (env (gFamily.getD 5 .canceled)) bound (.uncancelable (uid 1)))).all (fun o => (obsList (exploreP {} counterMaskModel (env (gFamily.getD 5 .canceled)) bound (allocatedCaseFixed 0))).contains o)) = true := by
  decide +kernel

end CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed
