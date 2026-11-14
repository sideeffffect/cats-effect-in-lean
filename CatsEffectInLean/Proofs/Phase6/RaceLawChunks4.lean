import CatsEffectInLean.Proofs.Phase6.RaceLawChunks3

/-! Edge checks of the left side of `uncancelableRaceNotInherited`, states 2584 to 2999
(see `Proofs/Phase6/RaceLaw.lean`). Each module imports the previous one, so the chunks are
checked one after another; chunk sizes keep each `decide` below about 7.5 GB. -/

namespace CatsEffectInLean.Proofs.Phase6.RaceLaw

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Race
open CatsEffectInLean.Proofs.Lemmas.CertP

set_option maxHeartbeats 0 in
theorem lhs_chunk_20 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      2584 84 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_21 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      2668 84 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_22 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      2752 84 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_23 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      2836 84 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_24 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      2920 80 = true := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.RaceLaw
