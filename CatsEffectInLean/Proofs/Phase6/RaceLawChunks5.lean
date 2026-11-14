import CatsEffectInLean.Proofs.Phase6.RaceLawChunks4

/-! Edge checks of the left side of `uncancelableRaceNotInherited`, states 3000 to 3419
(see `Proofs/Phase6/RaceLaw.lean`). Each module imports the previous one, so the chunks are
checked one after another; chunk sizes keep each `decide` below about 7.5 GB. -/

namespace CatsEffectInLean.Proofs.Phase6.RaceLaw

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Race
open CatsEffectInLean.Proofs.Lemmas.CertP

set_option maxHeartbeats 0 in
theorem lhs_chunk_25 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      3000 84 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_26 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      3084 84 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_27 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      3168 84 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_28 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      3252 84 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_29 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      3336 84 = true := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.RaceLaw
