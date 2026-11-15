import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.OldOnePreemptA
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.OldOnePreemptB

/-! The CE-0030 check `old_onePreempt` (`MemoizeFixed.lean`) from its two halves (`Half/`). -/

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

/-- v3.7.1 is blocked exactly at positions 35, 36, 37 (positions below 120). -/
theorem old_onePreempt :
    (List.range 120).filter (fun i => onePreempt 0 i == some .blocked) = [35, 36, 37] := by
  rw [show (120 : Nat) = 60 + 60 from rfl, range_split, List.filter_append, old_onePreempt_a, old_onePreempt_b]; rfl

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
