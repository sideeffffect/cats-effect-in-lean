import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FamFixedCedeCanceled2A
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FamFixedCedeCanceled2B

/-! The CE-0030 check `fam_fixed_cedeCanceled2` (`MemoizeFixed.lean`) from its two halves (`Half/`). -/

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

theorem fam_fixed_cedeCanceled2 :
    grid.all (fun (i, j) => isDone (two faCedeCanceled 1 i j)) = true := by
  rw [grid_split, List.all_append, fam_fixed_cedeCanceled2_a, fam_fixed_cedeCanceled2_b]; rfl

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
