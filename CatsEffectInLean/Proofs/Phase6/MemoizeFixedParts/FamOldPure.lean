import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FamOldPureA
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FamOldPureB

/-! The CE-0030 check `fam_old_pure` (`MemoizeFixed.lean`) from its two halves (`Half/`). -/

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

theorem fam_old_pure : oldStuck faPure = [] := by
  unfold oldStuck
  rw [show (120 : Nat) = 60 + 60 from rfl, range_split, List.filter_append, fam_old_pure_a, fam_old_pure_b]; rfl

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
