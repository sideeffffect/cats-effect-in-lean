import CatsEffectInLean.Proofs.Phase6.RaceLawDefs

/-! Edge checks of the left side of `uncancelableRaceNotInherited`, states 3724 to 3999
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
theorem lhs_chunk_35 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      3724 56 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_36 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      3780 56 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_37 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      3836 56 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_38 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      3892 56 = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_chunk_39 :
    certChunk {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ
      3948 52 = true := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.RaceLaw
