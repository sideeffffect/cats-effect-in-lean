import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FamFixedErrorA
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FamFixedErrorB

/-! The CE-0030 check `fam_fixed_error` (`MemoizeFixed.lean`) from its two halves (`Half/`). -/

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

theorem fam_fixed_error : fixedOK faError = true := by
  unfold fixedOK
  rw [show (120 : Nat) = 60 + 60 from rfl, range_split, List.all_append, fam_fixed_error_a, fam_fixed_error_b]; rfl

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
