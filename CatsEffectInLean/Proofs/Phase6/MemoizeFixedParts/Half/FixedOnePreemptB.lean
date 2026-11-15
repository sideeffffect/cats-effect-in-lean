import CatsEffectInLean.Proofs.Phase6.MemoizeFixedDefs

/-! Half B of the CE-0030 check `fixed_onePreempt` (`MemoizeFixedParts/FixedOnePreempt.lean`), for memory. -/

set_option Elab.async false

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

theorem fixed_onePreempt_b :
    (List.range' 60 60).all (fun i => onePreempt 1 i != some .blocked) = true := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
