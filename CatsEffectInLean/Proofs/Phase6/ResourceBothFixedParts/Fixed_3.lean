import CatsEffectInLean.Proofs.Phase6.ResourceBothFixedDefs

/-! One chunk of the CE-0020 fixed-twin check (`ResourceBothFixed.lean`), in its own file for memory.
One theorem per value of `k` (2 schedules, about 5 GB of kernel memory each; the kernel frees it
between theorems). `Elab.async false`: the theorems are checked one after the other, so the peak
is one theorem, not several in parallel. -/

set_option Elab.async false

namespace CatsEffectInLean.Proofs.Phase6.ResourceBothFixed

open CatsEffectInLean.Model
open CatsEffectInLean.Model.ResourceUse
open CatsEffectInLean.Props.Phase6.Resource
open CatsEffectInLean.Proofs.Phase6.ResourceWitnessEnv
open CatsEffectInLean.Proofs.Phase6.ResourceBothWitness

set_option maxHeartbeats 0 in
theorem fixed_k78 : (family 78 1).all (okOn fixedBody) = true := by decide +kernel

set_option maxHeartbeats 0 in
theorem fixed_k79 : (family 79 1).all (okOn fixedBody) = true := by decide +kernel

set_option maxHeartbeats 0 in
theorem fixed_k80 : (family 80 1).all (okOn fixedBody) = true := by decide +kernel

set_option maxHeartbeats 0 in
theorem fixed_k81 : (family 81 1).all (okOn fixedBody) = true := by decide +kernel

set_option maxHeartbeats 0 in
theorem fixed_k82 : (family 82 1).all (okOn fixedBody) = true := by decide +kernel

end CatsEffectInLean.Proofs.Phase6.ResourceBothFixed
