import CatsEffectInLean.Proofs.Phase6.RaceLawChunks9

/-!
# `GenSpawnLaws.uncancelableRaceNotInherited` for `IO` (Phase 6, track P)

`F.uncancelable(_ => F.race(F.never[Unit], F.canceled)).void <-> F.never[Unit]`
(`laws/shared/src/main/scala/cats/effect/laws/GenSpawnLaws.scala:121-122`), `<->` = `EqvP`.

Proof by certificates (`Proofs/Lemmas/CertP.lean`): the left side has exactly 4,441 states
(closed under `preempt` and every `pick`), the right side 45. On both sides every state with an
observation has the observation `blockedEmpty` (the run stops with no ready task; no emit, no
`Ref`, no report), and some state has it. So both outcome sets are `{blockedEmpty}`.

The certificates (`RaceLawCertLhs`, `RaceLawCertRhs`) come from the untrusted generator
`tools/CertGen/RaceLaw.lean`. The kernel checks them with `decide +kernel`. The edges of the
left side are checked in 49 chunks (`RaceLawChunks0` .. `RaceLawChunks9`).
-/

namespace CatsEffectInLean.Proofs.Phase6.RaceLaw

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Race
open CatsEffectInLean.Proofs.Lemmas.CertP

theorem rhs_exact :
    certExact {} counterMaskModel lawEnv Timeout.neverIO rhsInstrs RaceLawCertRhs.succ = true := by
  decide +kernel

theorem rhs_obs :
    certObsOnly {} counterMaskModel lawEnv Timeout.neverIO rhsInstrs blockedEmpty = true := by
  decide +kernel

set_option maxHeartbeats 0 in
theorem lhs_obs :
    certObsOnly {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs blockedEmpty = true := by
  decide +kernel

theorem lhs_succ_length : RaceLawCertLhs.succ.length ≤ 4441 := by decide +kernel

theorem lhs_exact :
    certExact {} counterMaskModel lawEnv raceNotInheritedLhs lhsInstrs RaceLawCertLhs.succ =
      true :=
  certExact_of_edgesUpTo _ _ _
    (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_chunk _ _ _ (edgesUpTo_zero _ _ _ lhs_chunk_0) lhs_chunk_0) lhs_chunk_1) lhs_chunk_2) lhs_chunk_3) lhs_chunk_4) lhs_chunk_5) lhs_chunk_6) lhs_chunk_7) lhs_chunk_8) lhs_chunk_9) lhs_chunk_10) lhs_chunk_11) lhs_chunk_12) lhs_chunk_13) lhs_chunk_14) lhs_chunk_15) lhs_chunk_16) lhs_chunk_17) lhs_chunk_18) lhs_chunk_19) lhs_chunk_20) lhs_chunk_21) lhs_chunk_22) lhs_chunk_23) lhs_chunk_24) lhs_chunk_25) lhs_chunk_26) lhs_chunk_27) lhs_chunk_28) lhs_chunk_29) lhs_chunk_30) lhs_chunk_31) lhs_chunk_32) lhs_chunk_33) lhs_chunk_34) lhs_chunk_35) lhs_chunk_36) lhs_chunk_37) lhs_chunk_38) lhs_chunk_39) lhs_chunk_40) lhs_chunk_41) lhs_chunk_42) lhs_chunk_43) lhs_chunk_44) lhs_chunk_45) lhs_chunk_46) lhs_chunk_47) lhs_chunk_48)
    lhs_succ_length

theorem uncancelableRaceNotInherited_proven : uncancelableRaceNotInherited := by
  intro o
  rw [outcomesP_iff_of_certObsOnly _ _ _ lhs_exact lhs_obs,
    outcomesP_iff_of_certObsOnly _ _ _ rhs_exact rhs_obs]

end CatsEffectInLean.Proofs.Phase6.RaceLaw
