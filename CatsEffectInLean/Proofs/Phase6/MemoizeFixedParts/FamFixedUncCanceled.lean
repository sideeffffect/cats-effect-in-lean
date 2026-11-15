import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FamFixedUncCanceledA
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FamFixedUncCanceledB

/-! The CE-0030 check `fam_fixed_uncCanceled` (`MemoizeFixed.lean`) from its two halves (`Half/`). -/

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

theorem fam_fixed_uncCanceled : fixedOK faUncCanceled = true := by
  unfold fixedOK
  rw [show (120 : Nat) = 60 + 60 from rfl, range_split, List.all_append, fam_fixed_uncCanceled_a, fam_fixed_uncCanceled_b]; rfl

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
