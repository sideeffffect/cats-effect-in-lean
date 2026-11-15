import CatsEffectInLean.Proofs.Phase6.BracketSmokeDefs

/-! One check of `BracketSmoke.lean` (`law_5_4`), in its own file for memory. -/

set_option Elab.async false

namespace CatsEffectInLean.Proofs.Phase6.BracketSmoke

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Bracket
open CatsEffectInLean.Model.BracketExamples
open CatsEffectInLean.Props.Phase6.Bracket

theorem law_5_4 : checkEqvP {} counterMaskModel env 400 (lawL 5 4) (lawR 5 4) = true := by decide +kernel

end CatsEffectInLean.Proofs.Phase6.BracketSmoke
