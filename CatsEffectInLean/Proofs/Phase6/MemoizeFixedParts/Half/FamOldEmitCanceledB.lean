import CatsEffectInLean.Proofs.Phase6.MemoizeFixedDefs

/-! Half B of the CE-0030 check `fam_old_emitCanceled` (`MemoizeFixedParts/FamOldEmitCanceled.lean`), for memory. -/

set_option Elab.async false

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

theorem fam_old_emitCanceled_b :
    (List.range' 60 60).filter (fun i => stuck (one faEmitCanceled 0 i)) = [] := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
