import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedChecks

/-! One CE-0002 fixed-twin check (`ResourceEvalFixedChecks.lean`), in its own file for memory. -/

namespace CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceFixed

theorem old_canceled : oldFails (gFamily.getD 0 .canceled) = true := by decide +kernel

end CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed
