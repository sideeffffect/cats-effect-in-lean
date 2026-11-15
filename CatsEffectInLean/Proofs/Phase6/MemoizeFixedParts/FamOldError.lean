import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FamOldErrorA
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FamOldErrorB

/-! The CE-0030 check `fam_old_error` (`MemoizeFixed.lean`) from its two halves (`Half/`). -/

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

theorem fam_old_error : oldStuck faError = [] := by
  unfold oldStuck
  rw [show (120 : Nat) = 60 + 60 from rfl, range_split, List.filter_append, fam_old_error_a, fam_old_error_b]; rfl

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
