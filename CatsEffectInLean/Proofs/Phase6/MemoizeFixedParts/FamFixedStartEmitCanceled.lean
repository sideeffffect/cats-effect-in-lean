import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FamFixedStartEmitCanceledA
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FamFixedStartEmitCanceledB

/-! The CE-0030 check `fam_fixed_startEmitCanceled` (`MemoizeFixed.lean`) from its two halves (`Half/`). -/

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

theorem fam_fixed_startEmitCanceled : fixedOK faStartEmitCanceled = true := by
  unfold fixedOK
  rw [show (120 : Nat) = 60 + 60 from rfl, range_split, List.all_append, fam_fixed_startEmitCanceled_a, fam_fixed_startEmitCanceled_b]; rfl

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
