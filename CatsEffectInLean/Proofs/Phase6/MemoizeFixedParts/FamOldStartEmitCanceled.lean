import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FamOldStartEmitCanceledA
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FamOldStartEmitCanceledB

/-! The CE-0030 check `fam_old_startEmitCanceled` (`MemoizeFixed.lean`) from its two halves (`Half/`). -/

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

theorem fam_old_startEmitCanceled : oldStuck faStartEmitCanceled = [35, 36, 37] := by
  unfold oldStuck
  rw [show (120 : Nat) = 60 + 60 from rfl, range_split, List.filter_append, fam_old_startEmitCanceled_a, fam_old_startEmitCanceled_b]; rfl

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
