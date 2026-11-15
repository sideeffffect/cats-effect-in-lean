import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.Half.Law88Lhs
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.Half.Law88Rhs
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.Half.Law88Obs

/-! The smoke check `law_8_8` (`BracketSmoke.lean`) from its three parts (`Half/`: the exact
outcome set of each side, and the comparison of the two sets). -/

namespace CatsEffectInLean.Proofs.Phase6.BracketSmoke

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Bracket
open CatsEffectInLean.Model.BracketExamples
open CatsEffectInLean.Props.Phase6.Bracket

theorem law_8_8 : checkEqvP {} counterMaskModel env 400 (lawL 8 8) (lawR 8 8) = true := by
  have h1 := law_8_8_lhs
  have h2 := law_8_8_rhs
  have h3 := law_8_8_obs
  simp only [checkEqvP]
  rw [h1, h2, Bool.true_and, Bool.true_and]
  exact h3

end CatsEffectInLean.Proofs.Phase6.BracketSmoke
