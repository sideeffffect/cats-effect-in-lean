import CatsEffectInLean.Proofs.Phase6.BracketSmokeDefs

/-! One check of `BracketSmoke.lean` (`law_2_3`), in its own file for memory. -/

set_option Elab.async false

namespace CatsEffectInLean.Proofs.Phase6.BracketSmoke

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Bracket
open CatsEffectInLean.Model.BracketExamples
open CatsEffectInLean.Props.Phase6.Bracket

theorem law_2_3 : checkEqvP {} counterMaskModel env 400 (lawL 2 3) (lawR 2 3) = true := by decide +kernel

end CatsEffectInLean.Proofs.Phase6.BracketSmoke
