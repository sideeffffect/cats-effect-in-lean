import CatsEffectInLean.Proofs.Phase6.RaceLawChunks8

/-! Edge checks of the left side of `uncancelableRaceNotInherited`, states 4245 to 4440
(see `Proofs/Phase6/RaceLaw.lean`). Each module imports the previous one, so the chunks are
checked one after another; chunk sizes keep each `decide` below about 7.5 GB. -/

namespace CatsEffectInLean.Proofs.Phase6.RaceLaw

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Race
open CatsEffectInLean.Proofs.Lemmas.CertP

set_option maxHeartbeats 0 in
theorem lhs_chunk_45 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      4245 49 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_46 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      4294 49 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_47 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      4343 49 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_48 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      4392 49 = true := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.RaceLaw
