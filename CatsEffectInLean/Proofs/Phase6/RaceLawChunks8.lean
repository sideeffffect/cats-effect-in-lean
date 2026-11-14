import CatsEffectInLean.Proofs.Phase6.RaceLawChunks7

/-! Edge checks of the left side of `uncancelableRaceNotInherited`, states 4000 to 4244
(see `Proofs/Phase6/RaceLaw.lean`). Each module imports the previous one, so the chunks are
checked one after another; chunk sizes keep each `decide` below about 7.5 GB. -/

namespace CatsEffectInLean.Proofs.Phase6.RaceLaw

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Race
open CatsEffectInLean.Proofs.Lemmas.CertP

set_option maxHeartbeats 0 in
theorem lhs_chunk_40 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      4000 49 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_41 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      4049 49 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_42 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      4098 49 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_43 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      4147 49 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_44 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      4196 49 = true := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.RaceLaw
