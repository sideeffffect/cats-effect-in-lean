import CatsEffectInLean.Proofs.Phase6.MemoizeFixedDefs

/-! Half B of the CE-0030 check `fam_fixed_pure` (`MemoizeFixedParts/FamFixedPure.lean`), for memory. -/

set_option Elab.async false

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

theorem fam_fixed_pure_b :
    (List.range' 60 60).all (fun i => isDone (one faPure 1 i)) = true := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
