import CatsEffectInLean.Proofs.Phase6.RaceLawChunks1

/-! Edge checks of the left side of `uncancelableRaceNotInherited`, states 1500 to 2099
(see `Proofs/Phase6/RaceLaw.lean`). Each module imports the previous one, so the chunks are
checked one after another; chunk sizes keep each `decide` below about 7.5 GB. -/

namespace CatsEffectInLean.Proofs.Phase6.RaceLaw

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Race
open CatsEffectInLean.Proofs.Lemmas.CertP

set_option maxHeartbeats 0 in
theorem lhs_chunk_10 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      1500 125 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_11 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      1625 125 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_12 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      1750 125 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_13 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      1875 125 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_14 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      2000 100 = true := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.RaceLaw
