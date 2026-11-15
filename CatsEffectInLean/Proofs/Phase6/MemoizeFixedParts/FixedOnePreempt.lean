import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FixedOnePreemptA
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FixedOnePreemptB

/-! The CE-0030 check `fixed_onePreempt` (`MemoizeFixed.lean`) from its two halves (`Half/`). -/

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

/-- The fixed twin is never blocked with one preemption at a position below 120. -/
theorem fixed_onePreempt :
    (List.range 120).all (fun i => onePreempt 1 i != some .blocked) = true := by
  rw [show (120 : Nat) = 60 + 60 from rfl, range_split, List.all_append, fixed_onePreempt_a, fixed_onePreempt_b]; rfl

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
