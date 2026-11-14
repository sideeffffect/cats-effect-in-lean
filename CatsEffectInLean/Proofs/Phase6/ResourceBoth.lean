import CatsEffectInLean.Proofs.Phase6.ResourceWitness

/-!
# Refutation of `bothReleasesBoth` (CE-0020)

Witness (the program of `reproducers/CE-0020/Repro.scala`), environment
`ResourceWitnessEnv.W true true false`:

* side A (code `nat 20`): `make(IO.unit.map(_ => emit A))(_ => IO.delay(emit RA) *> IO.raiseError(boom))`;
* side B (code `nat 21`): `make(IO.unit.map(_ => emit B))(_ => IO.delay(emit RB) *> IO.unit)`;
* `Resource.both(A, B).use(_ => IO.unit)`, at the root (no parent).

Schedule `sched`: FIFO for 89 choices, then `pick 1`. Both sides are acquired. In the release
of `makeCase` (`Resource.scala:302-305`), `F.both` starts one fiber per finalizer chain. The
chain of A raises `boom`; the root fiber (the `F.both` body) then runs before the fiber of B's
chain, takes the `Errored` branch and cancels that fiber (`GenSpawn.scala:476-498`). That fiber
has not started, so it ends `Canceled` and runs nothing: `RB` is never emitted. The root ends
`Errored(boom)` with trace `[RA, B, A]` (newest first). So `count RB = 0 ≠ 1 = count B`.

The hypotheses hold, including the harness-name hypothesis `NoForge` (decision 54): no user
function mentions a harness name (`userR_clean`), user `Bind` functions fail, the other acquire,
release and resource codes are unused. This is also the satisfiability witness of statement 1
(decision 53).

Fixed twin (decision 39): `ResourceUse.fixedBothRes` satisfies the conclusion of the statement on
the same (well-formed, hypothesis-satisfying) input for the 120 single-deviation schedules around the release phase
(`Proofs/Phase6/ResourceBothFixed.lean`, `lean_lib TwinChecks`, kernel-checked), where v3.7.1 has
a violation; and (`#guard`) on all 600 single-deviation and 1,500 random schedules with preemption (`test/Phase6/ResourceSmoke.lean`).
-/

namespace CatsEffectInLean.Proofs.Phase6.ResourceBothWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceUse
open CatsEffectInLean.Props.Phase6.Resource
open CatsEffectInLean.Props.Phase6.HarnessNames
open CatsEffectInLean.Proofs.Phase6.ResourceWitnessEnv
open CatsEffectInLean.Proofs.Phase6.ResourceWitness (obs_of_run)

abbrev WB : UEnv := W true true false

/-- `Resource.both(A, B).use(_ => IO.unit)` (v3.7.1). -/
def prog : IO := useOf WB 14 (bothRes (.nat 20) (.nat 21))

/-- The fixed twin on the same input. -/
def fixedProg : IO := useOf WB 14 (fixedBothRes (.nat 20) (.nat 21))

/-- The schedule: FIFO for 89 choices, then `pick 1`. -/
def sched : List PChoice := List.replicate 89 (PChoice.pick 0) ++ [.pick 1]

theorem run_witness :
    (runObsP {} counterMaskModel (envH WB) 6000 sched (withParent false prog)).map (fun o => (o.summary, o.out)) =
      some (.done (.errored boom), [RA, B, A]) := by
  decide +kernel

theorem both_noForge :
    NoForge WB badBoth [2 * 1, 2 * 2, 2 * 3, 2 * 4] [0, 1] [0, 1] [] [.nat 20, .nat 21] := by
  refine ⟨fun id hid _ a v h => ?_, fun k a r _ hb => ?_, fun k hk => ?_, fun k a q hk hq h => ?_,
    fun c r hc h => ?_⟩
  · rw [toEnv_callV_even _ _ _ id hid, userR_clean _ (.inr (.inl rfl))] at h; cases h
  · simp [WB, W, renv] at hb
  · have h0 : k ≠ 0 := by simp at hk; omega
    have h1 : k ≠ 1 := by simp at hk; omega
    simp only [WB, W, renv, beq_iff_eq, h0, h1, ite_false]; decide +kernel
  · have h0 : k ≠ 0 := by simp at hk; omega
    have h1 : k ≠ 1 := by simp at hk; omega
    simp [WB, W, renv, h0, h1] at hq; subst hq
    exact absurd h (by decide +kernel)
  · simp only [WB, W] at h
    split at h <;> simp_all

theorem markedA : MarkedMake WB badBoth (.nat 20) 0 0 (.pure .unit) 1 3 A RA :=
  ⟨rfl, rfl, mapMarker _ _ _ 1 A rfl, marker _ _ _ 3 RA rfl, fun _ => ⟨5, rfl, by decide +kernel⟩,
    by decide +kernel⟩

theorem markedB : MarkedMake WB badBoth (.nat 21) 1 1 (.pure .unit) 2 4 B RB :=
  ⟨rfl, rfl, mapMarker _ _ _ 2 B rfl, marker _ _ _ 4 RB rfl, fun _ => ⟨6, rfl, by decide +kernel⟩,
    by decide +kernel⟩

theorem emits : EmitsOnly WB.toEnv [2 * 1, 2 * 2, 2 * 3, 2 * 4] [A, B, RA, RB] :=
  emitsOnly _ _ _ _ _ fun n h1 h4 hm x hx => by
    match n, h1, h4, hm with
    | 1, _, _, hm | 2, _, _, hm | 3, _, _, hm | 4, _, _, hm => simp at hm

theorem prog_wf : WellFormed isLibH [] (envH WB) (withParent false prog) :=
  wellFormed _ _ _ _ (by decide +kernel)

end CatsEffectInLean.Proofs.Phase6.ResourceBothWitness

namespace CatsEffectInLean.Proofs.Phase6

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Resource
open ResourceBothWitness ResourceWitnessEnv in
theorem bothReleasesBoth_refuted : ¬ bothReleasesBoth := by
  intro h
  obtain ⟨o, ho, hs, hout⟩ := ResourceWitness.obs_of_run run_witness
  have hc := h WB (.nat 20) (.nat 21) 0 0 1 1 (.pure .unit) (.pure .unit) 1 2 3 4 14 A B RA RB
    false markedA markedB (by decide +kernel) emits both_noForge (by decide +kernel) prog_wf o ho ⟨_, hs⟩
  rw [hout] at hc
  exact absurd hc.2 (by decide +kernel)

end CatsEffectInLean.Proofs.Phase6
