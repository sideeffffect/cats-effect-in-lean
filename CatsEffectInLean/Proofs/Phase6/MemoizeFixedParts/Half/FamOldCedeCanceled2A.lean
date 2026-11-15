import CatsEffectInLean.Proofs.Phase6.MemoizeFixedDefs

/-! Half A of the CE-0030 check `fam_old_cedeCanceled2` (`MemoizeFixedParts/FamOldCedeCanceled2.lean`), for memory. -/

set_option Elab.async false

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

theorem fam_old_cedeCanceled2_a :
    (gridOn 0 5).filter (fun (i, j) => stuck (two faCedeCanceled 0 i j)) = [(34, 12), (34, 13), (34, 14)] := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
