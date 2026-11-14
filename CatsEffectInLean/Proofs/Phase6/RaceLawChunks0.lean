import CatsEffectInLean.Proofs.Phase6.RaceLawDefs

/-! Edge checks of the left side of `uncancelableRaceNotInherited`, states 0 to 749
(see `Proofs/Phase6/RaceLaw.lean`). Each module imports the previous one, so the chunks are
checked one after another; chunk sizes keep each `decide` below about 7.5 GB. -/

namespace CatsEffectInLean.Proofs.Phase6.RaceLaw

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Race
open CatsEffectInLean.Proofs.Lemmas.CertP

set_option maxHeartbeats 0 in
theorem lhs_chunk_0 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      0 167 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_1 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      167 167 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_2 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      334 166 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_3 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      500 125 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_4 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      625 125 = true := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.RaceLaw
