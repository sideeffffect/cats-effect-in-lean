import CatsEffectInLean.Proofs.Phase6.MemoizeFixedDefs

/-! Half B of the CE-0030 check `fam_old_canceled` (`MemoizeFixedParts/FamOldCanceled.lean`), for memory. -/

set_option Elab.async false

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

theorem fam_old_canceled_b :
    (List.range' 60 60).filter (fun i => stuck (one .canceled 0 i)) = [] := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
