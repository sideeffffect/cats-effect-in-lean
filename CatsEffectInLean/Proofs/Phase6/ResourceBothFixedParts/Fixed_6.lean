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
theorem fixed_k93 : (family 93 1).all (okOn fixedBody) = true := by decide +kernel

set_option maxHeartbeats 0 in
theorem fixed_k94 : (family 94 1).all (okOn fixedBody) = true := by decide +kernel

set_option maxHeartbeats 0 in
theorem fixed_k95 : (family 95 1).all (okOn fixedBody) = true := by decide +kernel

set_option maxHeartbeats 0 in
theorem fixed_k96 : (family 96 1).all (okOn fixedBody) = true := by decide +kernel

set_option maxHeartbeats 0 in
theorem fixed_k97 : (family 97 1).all (okOn fixedBody) = true := by decide +kernel

end CatsEffectInLean.Proofs.Phase6.ResourceBothFixed
