import CatsEffectInLean.Proofs.Phase6.MemoizeFixedDefs

/-! Half A of the CE-0030 check `fam_old_uncCanceled` (`MemoizeFixedParts/FamOldUncCanceled.lean`), for memory. -/

set_option Elab.async false

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

theorem fam_old_uncCanceled_a :
    (List.range' 0 60).filter (fun i => stuck (one faUncCanceled 0 i)) = [35, 36, 37] := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
