import CatsEffectInLean.Proofs.Phase6.ResourceWitness

/-!
# Refutation of `bothReleasesBoth` (CE-0020)

Witness (the program of `reproducers/CE-0020/Repro.scala`), environment
`ResourceWitnessEnv.W true true false`:

* side A (code `cA`): `make(IO.unit.flatMap(markA A))(_ => IO.delay(markT RA) *> IO.raiseError(boom))`;
* side B (code `cB`): `make(IO.unit.flatMap(markA B))(_ => IO.delay(markT RB) *> IO.unit)`;
* `Resource.both(A, B).use(_ => IO.unit)`, run by the harness (log cell first), no parent.

Schedule `sched`: FIFO for 92 choices, then `pick 1`. Both sides are acquired. In the release of
`makeCase` (`Resource.scala:302-305`), `F.both` starts one fiber per finalizer chain. The chain of
A raises `boom`; the root fiber (the `F.both` body) then runs before the fiber of B's chain, takes
the `Errored` branch and cancels that fiber (`GenSpawn.scala:476-498`). That fiber has not
started, so it runs nothing: `RB` is never logged. The root ends `Errored(boom)` with log
`[A, B, RA]`. So `count RB = 0 ≠ 1 = count B`.

All hypotheses are proven, also `Private` (no user code names the token) and `WellFormed` with
the deep `Lib`: this is the satisfiability witness of statement 1 (decision 53).

Fixed twin (decision 39): `ResourceUse.fixedBothRes` satisfies the conclusion on the same input
for the 120 single-deviation schedules around the release phase
(`Proofs/Phase6/ResourceBothFixed.lean`, `lean_lib TwinChecks`, kernel-checked), where v3.7.1 has a
violation; and (`#guard`) on all 600 single-deviation and 1,500 random schedules with preemption
(`test/Phase6/ResourceSmoke.lean`).
-/

namespace CatsEffectInLean.Proofs.Phase6.ResourceBothWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceUse
open CatsEffectInLean.Props.Phase6.Resource
open CatsEffectInLean.Props.Phase6.HarnessPrivacy
open CatsEffectInLean.Proofs.Phase6.ResourceWitnessEnv
open CatsEffectInLean.Proofs.Phase6.ResourceWitness (obs_of_run)

abbrev WB : UEnv := W true true false

/-- `Resource.both(A, B).use(_ => IO.unit)` (v3.7.1). -/
def body : IO := withParent false (useOf WB 14 (bothRes cA cB))

/-- The fixed twin on the same input. -/
def fixedBody : IO := withParent false (useOf WB 14 (fixedBothRes cA cB))

/-- The schedule: FIFO for 92 choices, then `pick 1`. -/
def sched : List PChoice := List.replicate 92 (PChoice.pick 0) ++ [.pick 1]

theorem run_witness :
    (runObsP {} counterMaskModel (envH WB body) 8000 sched harness).map (fun o => (o.summary, logOf o)) =
      some (.done (.errored boom), [tagA, tagB, tagRA]) := by
  decide +kernel

theorem both_private : Private WB [code 0, code 2] [code 1, code 3] [] [cA, cB] := by
  refine ⟨userPrivate _ _ _, fun k a r _ hb => ?_, fun k hk => ?_, fun k a q hk hq => ?_, fun c r hc h => ?_⟩
  · simp [WB, W, renv] at hb
  · have h0 : k ≠ code 0 := by simp at hk; exact hk.1
    have h2 : k ≠ code 2 := by simp at hk; exact hk.2
    simp only [WB, W, renv, beq_iff_eq, h0, h2, ite_false, Bool.true_and]; decide +kernel
  · have h1 : k ≠ code 1 := by simp at hk; exact hk.1
    have h3 : k ≠ code 3 := by simp at hk; exact hk.2
    simp [WB, W, renv, h1, h3] at hq; subst hq; decide +kernel
  · have hA : c ≠ cA := by simp at hc; exact hc.1
    have hB : c ≠ cB := by simp at hc; exact hc.2
    simp [WB, W, hA, hB] at h

end CatsEffectInLean.Proofs.Phase6.ResourceBothWitness

namespace CatsEffectInLean.Proofs.Phase6

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Resource
open ResourceBothWitness ResourceWitnessEnv in
theorem bothReleasesBoth_refuted : ¬ bothReleasesBoth := by
  intro h
  obtain ⟨o, ho, hs, hl⟩ := ResourceWitness.obs_of_run run_witness
  have hc := h WB cA cB (code 0) (code 1) (code 2) (code 3) (.pure .unit) (.pure .unit) 14 false
    (markedA _ _ _) (markedB _ _) both_private (wellFormed _ _ _ _) o ho ⟨_, hs⟩
  rw [hl] at hc
  exact absurd hc.2 (by decide +kernel)

end CatsEffectInLean.Proofs.Phase6
