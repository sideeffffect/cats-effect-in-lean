import CatsEffectInLean.Proofs.Phase6.RaceLawDefs

/-! Edge checks of the left side of `uncancelableRaceNotInherited`, states 1500 to 2099
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
