import CatsEffectInLean.Proofs.Phase6.BracketSmokeDefs

/-! One check of `BracketSmoke.lean` (`twin_pure_u_8`), in its own file for memory. -/

set_option Elab.async false

namespace CatsEffectInLean.Proofs.Phase6.BracketSmoke

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Bracket
open CatsEffectInLean.Model.BracketExamples
open CatsEffectInLean.Props.Phase6.Bracket

theorem twin_pure_u_8 : checkEqvP {} counterMaskModel env 400 (bracketFullIO (uid 0 [.nat 6]) (uid 0 [.nat 8]) (uid 2 [.nat 9]))
    (defaultBracketFullIO (uid 0 [.nat 6]) (uid 0 [.nat 8]) (uid 2 [.nat 9])) = true := by decide +kernel

end CatsEffectInLean.Proofs.Phase6.BracketSmoke
