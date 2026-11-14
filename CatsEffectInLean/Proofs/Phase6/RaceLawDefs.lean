import CatsEffectInLean.Proofs.Lemmas.CertP
import CatsEffectInLean.Props.Phase6.Race
import CatsEffectInLean.Proofs.Phase6.RaceLawCertLhs
import CatsEffectInLean.Proofs.Phase6.RaceLawCertRhs

/-! Definitions for `Proofs/Phase6/RaceLaw.lean`: the decoded certificates and the only
observation of both sides of `uncancelableRaceNotInherited`. -/

namespace CatsEffectInLean.Proofs.Phase6.RaceLaw

open CatsEffectInLean.Model
open CatsEffectInLean.Proofs.Lemmas.CertP

/-- The only observation of both sides: blocked, no emit, no `Ref`, no report. -/
def blockedEmpty : Obs := { summary := .blocked, out := [], refs := [], reports := [] }

def lhsInstrs : List (Option PChoice) := RaceLawCertLhs.instrs.map decodeInstr
def rhsInstrs : List (Option PChoice) := RaceLawCertRhs.instrs.map decodeInstr

end CatsEffectInLean.Proofs.Phase6.RaceLaw
