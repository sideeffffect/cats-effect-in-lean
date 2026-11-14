import CatsEffectInLean.Proofs.Phase6.ResourceWitnessEnv

/-!
# Satisfiability witnesses of the `Resource` statements (decision 53)

For `useReleaseOnce` and `flatMapReleaseOrder`, with and without the parent fiber: one concrete
input (`ResourceWitnessEnv.W`) that meets all hypotheses together, and a run that ends with a
root outcome in which the interesting case happens: every acquire marker and every release
marker ran once. So the hypotheses are not vacuous, and the conclusion is not trivially true.
(For `bothReleasesBoth` the CE-0020 refutation is the witness: `Proofs/Phase6/ResourceBoth.lean`.)

Schedules: FIFO without the parent; with the parent, three `pick 0` and one `preempt` (the root
yields after `start`; the child acquires, uses and releases before the parent's cancel lands, and
the parent joins `Succeeded`).
-/

namespace CatsEffectInLean.Proofs.Phase6.ResourceWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceUse
open CatsEffectInLean.Props.Phase6.Resource
open CatsEffectInLean.Props.Phase6.HarnessNames
open CatsEffectInLean.Proofs.Phase6.ResourceWitnessEnv

/-- A run as an observation in `outcomesP`. -/
theorem obs_of_run {env : UserEnv} {fuel : Nat} {cs : List PChoice} {p : IO} {s : Summary} {out : List Val}
    (h : (runObsP {} counterMaskModel env fuel cs p).map (fun o => (o.summary, o.out)) = some (s, out)) :
    ∃ o, outcomesP {} counterMaskModel env p o ∧ o.summary = s ∧ o.out = out := by
  rcases hr : runObsP {} counterMaskModel env fuel cs p with _ | o
  · rw [hr] at h; cases h
  · rw [hr] at h
    simp only [Option.map_some, Option.some.injEq, Prod.mk.injEq] at h
    exact ⟨o, ⟨fuel, cs, hr⟩, h.1, h.2⟩

/-- The schedule of the parent witnesses. -/
def parentSched : List PChoice := List.replicate 3 (PChoice.pick 0) ++ [.preempt]

def schedOf (viaParent : Bool) : List PChoice := if viaParent then parentSched else []

/-! ## `useReleaseOnce` -/

abbrev WU : UEnv := W false false false

def progUse (viaParent : Bool) : IO := withParent viaParent (useOf WU 14 (Res.make 0 0))

theorem use_noForge : NoForge WU badUse [2 * 1, 2 * 3] [0] [0] [] [.nat 20] := by
  refine ⟨fun id hid _ a v h => ?_, fun k a r _ hb => ?_, fun k hk => ?_, fun k a q hk hq h => ?_,
    fun c r hc h => ?_⟩
  · rw [toEnv_callV_even _ _ _ id hid, userR_clean _ (.inl rfl)] at h; cases h
  · simp [WU, W, renv] at hb
  · have h0 : k ≠ 0 := by simpa using hk
    by_cases h1 : k = 1
    · subst h1; decide +kernel
    · simp only [WU, W, renv, beq_iff_eq, h0, h1, ite_false]; decide +kernel
  · have h0 : k ≠ 0 := by simpa using hk
    by_cases h1 : k = 1
    · subst h1; simp [WU, W, renv] at hq; subst hq
      exact absurd h (by decide +kernel)
    · simp [WU, W, renv, h0, h1] at hq; subst hq
      exact absurd h (by decide +kernel)
  · simp only [WU, W] at h
    split at h <;> simp_all

theorem use_sat (viaParent : Bool) :
    MarkedMake WU badUse (.nat 20) 0 0 (.pure .unit) 1 3 A RA ∧ A ≠ RA ∧
    EmitsOnly WU.toEnv [2 * 1, 2 * 3] [A, RA] ∧
    NoForge WU badUse [2 * 1, 2 * 3] [0] [0] [] [.nat 20] ∧
    mentionsV badUse (.nat 14) = false ∧
    WellFormed isLibH [] (envH WU) (progUse viaParent) ∧
    ∃ o, outcomesP {} counterMaskModel (envH WU) (progUse viaParent) o ∧ (∃ oc, o.summary = .done oc) ∧
      o.out.count A = 1 ∧ o.out.count RA = 1 := by
  refine ⟨⟨rfl, rfl, mapMarker _ _ _ 1 A rfl, marker _ _ _ 3 RA rfl, fun _ => ⟨6, rfl, by decide +kernel⟩,
      by decide +kernel⟩, by decide +kernel, ?_, use_noForge, by decide +kernel, ?_, ?_⟩
  · refine emitsOnly _ _ _ _ _ fun n h1 h4 hm x hx => ?_
    match n, h1, h4, hm with
    | 2, _, _, _ | 4, _, _, _ => simp only [List.mem_cons, List.not_mem_nil, or_false] at hx
                                 rcases hx with rfl | rfl <;> decide +kernel
    | 1, _, _, hm | 3, _, _, hm => simp at hm
  · cases viaParent <;> exact wellFormed _ _ _ _ (by decide +kernel)
  · cases viaParent
    · obtain ⟨o, ho, hs, hout⟩ := obs_of_run (env := envH WU) (fuel := 6000) (cs := [])
        (p := progUse false) (s := .done (.succeeded .unit)) (out := [RA, A]) (by decide +kernel)
      exact ⟨o, ho, ⟨_, hs⟩, by rw [hout]; decide +kernel, by rw [hout]; decide +kernel⟩
    · obtain ⟨o, ho, hs, hout⟩ := obs_of_run (env := envH WU) (fuel := 6000) (cs := parentSched)
        (p := progUse true) (s := .done (.succeeded (.ocSucceeded .unit))) (out := [RA, A]) (by decide +kernel)
      exact ⟨o, ho, ⟨_, hs⟩, by rw [hout]; decide +kernel, by rw [hout]; decide +kernel⟩

/-! ## `flatMapReleaseOrder` -/

abbrev WF2 : UEnv := W false true true

def progFlat (viaParent : Bool) : IO := withParent viaParent (useOf WF2 14 ((Res.make 0 0).flatMap 9))

theorem flat_noForge :
    NoForge WF2 badFlat [2 * 1, 2 * 2, 2 * 3, 2 * 4] [0, 1] [0, 1] [9] [.nat 20, .nat 21] := by
  refine ⟨fun id hid _ a v h => ?_, fun k a r hk hb => ?_, fun k hk => ?_, fun k a q hk hq h => ?_,
    fun c r hc h => ?_⟩
  · rw [toEnv_callV_even _ _ _ id hid, userR_clean _ (.inr (.inr rfl))] at h; cases h
  · have h9 : k ≠ 9 := by simpa using hk
    simp [WF2, W, renv, h9] at hb
  · have h0 : k ≠ 0 := by simp at hk; omega
    have h1 : k ≠ 1 := by simp at hk; omega
    simp only [WF2, W, renv, beq_iff_eq, h0, h1, ite_false]; decide +kernel
  · have h0 : k ≠ 0 := by simp at hk; omega
    have h1 : k ≠ 1 := by simp at hk; omega
    simp [WF2, W, renv, h0, h1] at hq; subst hq
    exact absurd h (by decide +kernel)
  · simp only [WF2, W] at h
    split at h <;> simp_all

theorem flat_sat (viaParent : Bool) :
    MarkedMake WF2 badFlat (.nat 20) 0 0 (.pure .unit) 1 3 A RA ∧
    MarkedMake WF2 badFlat (.nat 21) 1 1 (.pure .unit) 2 4 B RB ∧
    (∀ x, WF2.r.bind 9 x = .ok (Res.make 1 1)) ∧
    [A, B, RA, RB].Nodup ∧
    EmitsOnly WF2.toEnv [2 * 1, 2 * 2, 2 * 3, 2 * 4] [A, B, RA, RB] ∧
    NoForge WF2 badFlat [2 * 1, 2 * 2, 2 * 3, 2 * 4] [0, 1] [0, 1] [9] [.nat 20, .nat 21] ∧
    mentionsV badFlat (.nat 14) = false ∧
    WellFormed isLibH [] (envH WF2) (progFlat viaParent) ∧
    ∃ o, outcomesP {} counterMaskModel (envH WF2) (progFlat viaParent) o ∧ (∃ oc, o.summary = .done oc) ∧
      o.out.count A = 1 ∧ o.out.count B = 1 ∧ o.out.count RA = 1 ∧ o.out.count RB = 1 := by
  refine ⟨⟨rfl, rfl, mapMarker _ _ _ 1 A rfl, marker _ _ _ 3 RA rfl, fun _ => ⟨6, rfl, by decide +kernel⟩,
      by decide +kernel⟩,
    ⟨rfl, rfl, mapMarker _ _ _ 2 B rfl, marker _ _ _ 4 RB rfl, fun _ => ⟨6, rfl, by decide +kernel⟩,
      by decide +kernel⟩, fun _ => rfl, by decide +kernel, ?_, flat_noForge, by decide +kernel, ?_, ?_⟩
  · refine emitsOnly _ _ _ _ _ fun n h1 h4 hm x hx => ?_
    match n, h1, h4, hm with
    | 1, _, _, hm | 2, _, _, hm | 3, _, _, hm | 4, _, _, hm => simp at hm
  · cases viaParent <;> exact wellFormed _ _ _ _ (by decide +kernel)
  · cases viaParent
    · obtain ⟨o, ho, hs, hout⟩ := obs_of_run (env := envH WF2) (fuel := 6000) (cs := [])
        (p := progFlat false) (s := .done (.succeeded .unit)) (out := [RA, RB, B, A]) (by decide +kernel)
      exact ⟨o, ho, ⟨_, hs⟩, by rw [hout]; decide +kernel, by rw [hout]; decide +kernel,
        by rw [hout]; decide +kernel, by rw [hout]; decide +kernel⟩
    · obtain ⟨o, ho, hs, hout⟩ := obs_of_run (env := envH WF2) (fuel := 6000) (cs := parentSched)
        (p := progFlat true) (s := .done (.succeeded (.ocSucceeded .unit))) (out := [RA, RB, B, A]) (by decide +kernel)
      exact ⟨o, ho, ⟨_, hs⟩, by rw [hout]; decide +kernel, by rw [hout]; decide +kernel,
        by rw [hout]; decide +kernel, by rw [hout]; decide +kernel⟩

end CatsEffectInLean.Proofs.Phase6.ResourceWitness
