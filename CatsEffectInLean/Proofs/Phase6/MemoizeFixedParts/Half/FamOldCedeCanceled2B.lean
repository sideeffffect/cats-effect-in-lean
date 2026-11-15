import CatsEffectInLean.Proofs.Phase6.MemoizeFixedDefs

/-! Half B of the CE-0030 check `fam_old_cedeCanceled2` (`MemoizeFixedParts/FamOldCedeCanceled2.lean`), for memory. -/

set_option Elab.async false

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

theorem fam_old_cedeCanceled2_b :
    (gridOn 5 5).filter (fun (i, j) => stuck (two faCedeCanceled 0 i j)) = [(35, 11), (35, 12), (35, 13), (36, 11), (36, 12), (37, 11)] := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
