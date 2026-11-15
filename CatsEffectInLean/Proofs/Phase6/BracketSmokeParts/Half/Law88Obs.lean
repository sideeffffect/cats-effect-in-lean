import CatsEffectInLean.Proofs.Phase6.BracketSmokeDefs

/-! One third of the smoke check `law_8_8` (`BracketSmokeParts/Law88.lean`), for memory. -/

set_option Elab.async false

namespace CatsEffectInLean.Proofs.Phase6.BracketSmoke

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Bracket
open CatsEffectInLean.Model.BracketExamples
open CatsEffectInLean.Props.Phase6.Bracket

theorem law_8_8_obs :
    ((obsList (exploreP {} counterMaskModel env 400 (lawL 8 8))).all (fun o => (obsList (exploreP {} counterMaskModel env 400 (lawR 8 8))).contains o) &&
      (obsList (exploreP {} counterMaskModel env 400 (lawR 8 8))).all (fun o => (obsList (exploreP {} counterMaskModel env 400 (lawL 8 8))).contains o)) = true := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.BracketSmoke
