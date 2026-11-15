import CatsEffectInLean.Proofs.Phase6.BracketSmokeDefs

/-! One third of the smoke check `law_8_8` (`BracketSmokeParts/Law88.lean`), for memory. -/

set_option Elab.async false

namespace CatsEffectInLean.Proofs.Phase6.BracketSmoke

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Bracket
open CatsEffectInLean.Model.BracketExamples
open CatsEffectInLean.Props.Phase6.Bracket

theorem law_8_8_lhs : exactP {} counterMaskModel env (lawL 8 8) (exploreP {} counterMaskModel env 400 (lawL 8 8)) = true := by decide +kernel

end CatsEffectInLean.Proofs.Phase6.BracketSmoke
