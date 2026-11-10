import CatsEffectInLean.Props.Phase6.Race

/-!
# Proofs for `Props/Phase6/Race.lean`

`uncancelableRaceNotInherited_proven`: the law has no input, so the exact outcome sets of both
sides are computed by `exploreP` and compared in the kernel (`checkEqvP`, `decide +kernel`).
Both sides: `blocked`, empty trace, no `Ref`, no report. On the left, `F.canceled` wins the race
(fiber 2 self-cancels), `race` cancels and joins the `never` side, both sides are `Canceled`, and
`poll(canceled) *> never` runs under the outer `uncancelable` (the race's `poll` restores the
outer mask), so the root waits forever.

The universal statements (`combNoLeak`, `combCanceledNoLeak`, `timeoutNoLeak`,
`raceOutcomeIsWinnerOutcome`) are `open`: a proof for all sides needs a simulation or invariant
argument over `Step`/`SchedP` (module doc of the registry entries).
-/

namespace CatsEffectInLean.Proofs.Phase6.Race

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Race

theorem uncancelableRaceNotInherited_check :
    checkEqvP {} counterMaskModel lawEnv 2000 raceNotInheritedLhs Timeout.neverIO = true := by
  decide +kernel

theorem uncancelableRaceNotInherited_proven :
    CatsEffectInLean.Props.Phase6.Race.uncancelableRaceNotInherited :=
  eqvP_of_checkEqvP {} counterMaskModel lawEnv uncancelableRaceNotInherited_check

end CatsEffectInLean.Proofs.Phase6.Race
