import CatsEffectInLean.Proofs.Phase6.RaceLawDefs

/-! Edge checks of the left side of `uncancelableRaceNotInherited`, states 3420 to 3723
(see `Proofs/Phase6/RaceLaw.lean`). Each chunk module imports only `RaceLawDefs`, so the CI
matrix builds and replays them in parallel jobs (decision 57). Do not build `HeavyProofs` with
plain parallel `lake build` on one machine: each module needs up to about 8 GB; use
`scripts/check_heavy_proofs.sh` (one module per Lean process). Chunk sizes keep each `decide`
below about 7.5 GB. -/

namespace CatsEffectInLean.Proofs.Phase6.RaceLaw

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Race
open CatsEffectInLean.Proofs.Lemmas.CertP

set_option maxHeartbeats 0 in
theorem lhs_chunk_30 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      3420 80 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_31 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      3500 56 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_32 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      3556 56 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_33 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      3612 56 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_34 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      3668 56 = true := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.RaceLaw
