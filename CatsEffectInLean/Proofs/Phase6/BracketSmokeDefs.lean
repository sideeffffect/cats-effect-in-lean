import CatsEffectInLean.Props.Phase6.Bracket
import CatsEffectInLean.Model.BracketExamples
import CatsEffectInLean.Model.EnumP

/-! Definitions of the `guarantee`/`bracket` smoke tests (`BracketSmoke.lean`); the checks are in
`BracketSmokeParts/`, one module each, for memory and for a parallel CI matrix. -/

namespace CatsEffectInLean.Proofs.Phase6.BracketSmoke

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Bracket
open CatsEffectInLean.Model.BracketExamples
open CatsEffectInLean.Props.Phase6.Bracket

/-! ## The law `guaranteeIsGuaranteeCase` -/

def lawL (s f : Nat) : IO := guaranteeIO (.ext (.nat s)) (.ext (.nat f))
def lawR (s f : Nat) : IO := guaranteeCaseIO (.ext (.nat s)) (uid 0 [.nat f])

end CatsEffectInLean.Proofs.Phase6.BracketSmoke
