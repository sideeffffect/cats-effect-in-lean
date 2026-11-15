import CatsEffectInLean.Proofs.Phase6.BracketSmokeDefs

/-! One check of `BracketSmoke.lean` (`law_wrongFunction`), in its own file for memory. -/

set_option Elab.async false

namespace CatsEffectInLean.Proofs.Phase6.BracketSmoke

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Bracket
open CatsEffectInLean.Model.BracketExamples
open CatsEffectInLean.Props.Phase6.Bracket

/-- Wrong-function test: a `guarantee` that never runs the finalizer (`fa` alone). -/
theorem law_wrongFunction : checkNotEqvP {} counterMaskModel env 400 (progOf (.nat 0)) (lawR 0 3) = true := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.BracketSmoke
