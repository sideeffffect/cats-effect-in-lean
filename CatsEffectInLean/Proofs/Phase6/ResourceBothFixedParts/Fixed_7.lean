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
theorem fixed_k98 : (family 98 1).all (okOn fixedBody) = true := by decide +kernel

set_option maxHeartbeats 0 in
theorem fixed_k99 : (family 99 1).all (okOn fixedBody) = true := by decide +kernel

set_option maxHeartbeats 0 in
theorem fixed_k100 : (family 100 1).all (okOn fixedBody) = true := by decide +kernel

set_option maxHeartbeats 0 in
theorem fixed_k101 : (family 101 1).all (okOn fixedBody) = true := by decide +kernel

set_option maxHeartbeats 0 in
theorem fixed_k102 : (family 102 1).all (okOn fixedBody) = true := by decide +kernel

end CatsEffectInLean.Proofs.Phase6.ResourceBothFixed
