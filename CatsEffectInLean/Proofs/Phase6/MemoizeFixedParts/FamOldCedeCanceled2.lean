import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FamOldCedeCanceled2A
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.Half.FamOldCedeCanceled2B

/-! The CE-0030 check `fam_old_cedeCanceled2` (`MemoizeFixed.lean`) from its two halves (`Half/`). -/

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

theorem fam_old_cedeCanceled2 :
    grid.filter (fun (i, j) => stuck (two faCedeCanceled 0 i j)) =
      [(34, 12), (34, 13), (34, 14), (35, 11), (35, 12), (35, 13), (36, 11), (36, 12), (37, 11)] := by
  rw [grid_split, List.filter_append, fam_old_cedeCanceled2_a, fam_old_cedeCanceled2_b]; rfl

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
