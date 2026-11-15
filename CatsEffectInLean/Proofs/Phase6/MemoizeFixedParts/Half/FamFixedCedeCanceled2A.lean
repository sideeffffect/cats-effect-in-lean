import CatsEffectInLean.Proofs.Phase6.MemoizeFixedDefs

/-! Half A of the CE-0030 check `fam_fixed_cedeCanceled2` (`MemoizeFixedParts/FamFixedCedeCanceled2.lean`), for memory. -/

set_option Elab.async false

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

theorem fam_fixed_cedeCanceled2_a :
    (gridOn 0 5).all (fun (i, j) => isDone (two faCedeCanceled 1 i j)) = true := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
