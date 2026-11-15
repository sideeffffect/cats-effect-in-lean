import CatsEffectInLean.Proofs.Phase6.MemoizeFixedDefs

/-! Half A of the CE-0030 check `fam_fixed_cedeCanceled` (`MemoizeFixedParts/FamFixedCedeCanceled.lean`), for memory. -/

set_option Elab.async false

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

theorem fam_fixed_cedeCanceled_a :
    (List.range' 0 60).all (fun i => isDone (one faCedeCanceled 1 i)) = true := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
