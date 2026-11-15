import CatsEffectInLean.Proofs.Phase6.MemoizeFixedDefs

/-! Half A of the CE-0030 check `old_onePreempt` (`MemoizeFixedParts/OldOnePreempt.lean`), for memory. -/

set_option Elab.async false

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

theorem old_onePreempt_a :
    (List.range' 0 60).filter (fun i => onePreempt 0 i == some .blocked) = [35, 36, 37] := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
