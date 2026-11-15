import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedChecks

/-! One third of the CE-0002 check `old_childCancel` (`Old_childCancel.lean`), in its own file for memory. -/

namespace CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceFixed

theorem old_childCancel_obs :
    ((obsList (exploreP {} counterMaskModel (env (gFamily.getD 5 .canceled)) bound allocOld)).all (fun o => (obsList (exploreP {} counterMaskModel (env (gFamily.getD 5 .canceled)) bound (.uncancelable (uid 2)))).contains o) &&
      (obsList (exploreP {} counterMaskModel (env (gFamily.getD 5 .canceled)) bound (.uncancelable (uid 2)))).all (fun o => (obsList (exploreP {} counterMaskModel (env (gFamily.getD 5 .canceled)) bound allocOld)).contains o)) = true := by
  decide +kernel

end CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed
