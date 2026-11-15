import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FamFixedEmitCanceledA
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FamFixedEmitCanceledB

/-! The CE-0030 check `fam_fixed_emitCanceled` (`MemoizeFixed.lean`) from its two halves (`Half/`). -/

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

theorem fam_fixed_emitCanceled : fixedOK faEmitCanceled = true := by
  unfold fixedOK
  rw [show (120 : Nat) = 60 + 60 from rfl, range_split, List.all_append, fam_fixed_emitCanceled_a, fam_fixed_emitCanceled_b]; rfl

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
