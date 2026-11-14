import CatsEffectInLean.Proofs.Phase6.RaceLawChunks0

/-! Edge checks of the left side of `uncancelableRaceNotInherited`, states 750 to 1499
(see `Proofs/Phase6/RaceLaw.lean`). Each module imports the previous one, so the chunks are
checked one after another; chunk sizes keep each `decide` below about 7.5 GB. -/

namespace CatsEffectInLean.Proofs.Phase6.RaceLaw

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Race
open CatsEffectInLean.Proofs.Lemmas.CertP

set_option maxHeartbeats 0 in
theorem lhs_chunk_5 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      750 125 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_6 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      875 125 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_7 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      1000 167 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_8 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      1167 167 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_9 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      1334 166 = true := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.RaceLaw
