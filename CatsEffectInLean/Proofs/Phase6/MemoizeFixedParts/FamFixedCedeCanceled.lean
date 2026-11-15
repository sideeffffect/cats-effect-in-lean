import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FamFixedCedeCanceledA
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FamFixedCedeCanceledB

/-! The CE-0030 check `fam_fixed_cedeCanceled` (`MemoizeFixed.lean`) from its two halves (`Half/`). -/

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

theorem fam_fixed_cedeCanceled : fixedOK faCedeCanceled = true := by
  unfold fixedOK
  rw [show (120 : Nat) = 60 + 60 from rfl, range_split, List.all_append, fam_fixed_cedeCanceled_a, fam_fixed_cedeCanceled_b]; rfl

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
