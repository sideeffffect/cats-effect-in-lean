import CatsEffectInLean.Proofs.Phase6.ResourceWitnessEnv

/-!
# Satisfiability witnesses of the `Resource` statements (decision 53)

For `useReleaseOnce` and `flatMapReleaseOrder`, with and without the parent fiber: one concrete
input (`ResourceWitnessEnv.W`) that meets all hypotheses together (marked `make`s with token-name
codes, `Private`, `WellFormed` with the deep `Lib`), and a run that ends with a root outcome in
which every acquire tag and every release tag is in the log once. So the hypotheses are not
vacuous, and the conclusion is not trivially true. (For `bothReleasesBoth` the CE-0020 refutation
is the witness: `Proofs/Phase6/ResourceBoth.lean`.)

Schedules: FIFO without the parent; with the parent, four `pick 0` and one `preempt` (the root
yields after `start`; the child acquires, uses and releases before the parent's cancel lands, and
the parent joins `Succeeded`).
-/

namespace CatsEffectInLean.Proofs.Phase6.ResourceWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceUse
open CatsEffectInLean.Props.Phase6.Resource
open CatsEffectInLean.Proofs.Phase6.ResourceWitnessEnv

/-- A run as an observation in `outcomesP`. -/
theorem obs_of_run {env : UserEnv} {fuel : Nat} {cs : List PChoice} {p : IO} {s : Summary} {l : List Val}
    (h : (runObsP {} counterMaskModel env fuel cs p).map (fun o => (o.summary, logOf o)) = some (s, l)) :
    ∃ o, outcomesP {} counterMaskModel env p o ∧ o.summary = s ∧ logOf o = l := by
  rcases hr : runObsP {} counterMaskModel env fuel cs p with _ | o
  · rw [hr] at h; cases h
  · rw [hr] at h
    simp only [Option.map_some, Option.some.injEq, Prod.mk.injEq] at h
    exact ⟨o, ⟨fuel, cs, hr⟩, h.1, h.2⟩

/-- The schedule of the parent witnesses. -/
def parentSched : List PChoice := List.replicate 4 (PChoice.pick 0) ++ [.preempt]

/-! ## `useReleaseOnce` -/

abbrev WU : UEnv := W false false false

def bodyUse (viaParent : Bool) : IO := withParent viaParent (useOf WU 14 (Res.make (code 0) (code 1)))

theorem use_private : Private WU [code 0] [code 1] [] [cA] := by
  refine ⟨fun k a r _ hb => ?_, fun k hk => ?_, fun k a q hk hq => ?_, fun c r hc h => ?_⟩
  · simp [WU, W, renv] at hb
  · have h0 : k ≠ code 0 := by simpa using hk
    simp only [WU, W, renv, beq_iff_eq, h0, ite_false, Bool.false_and]; decide +kernel
  · have h1 : k ≠ code 1 := by simpa using hk
    simp [WU, W, renv, h1] at hq; subst hq; rfl
  · have hA : c ≠ cA := by simpa using hc
    simp [WU, W, hA] at h

theorem use_sat (viaParent : Bool) :
    MarkedMake WU cA (code 0) (code 1) (.pure .unit) tagA tagRA ∧
    Private WU [code 0] [code 1] [] [cA] ∧
    WellFormed libH [] (envH WU (bodyUse viaParent)) harness ∧
    ∃ o, outcomesP {} counterMaskModel (envH WU (bodyUse viaParent)) harness o ∧
      (∃ oc, o.summary = .done oc) ∧ (logOf o).count tagA = 1 ∧ (logOf o).count tagRA = 1 := by
  refine ⟨markedA _ _ _, use_private, wellFormed _ _ _ _, ?_⟩
  cases viaParent
  · obtain ⟨o, ho, hs, hl⟩ := obs_of_run (env := envH WU (bodyUse false)) (fuel := 8000) (cs := [])
      (p := harness) (s := .done (.succeeded .unit)) (l := [tagA, tagRA]) (by decide +kernel)
    exact ⟨o, ho, ⟨_, hs⟩, by rw [hl]; decide +kernel, by rw [hl]; decide +kernel⟩
  · obtain ⟨o, ho, hs, hl⟩ := obs_of_run (env := envH WU (bodyUse true)) (fuel := 8000) (cs := parentSched)
      (p := harness) (s := .done (.succeeded (.ocSucceeded .unit))) (l := [tagA, tagRA]) (by decide +kernel)
    exact ⟨o, ho, ⟨_, hs⟩, by rw [hl]; decide +kernel, by rw [hl]; decide +kernel⟩

/-! ## `flatMapReleaseOrder` -/

abbrev WF2 : UEnv := W false true true

def bodyFlat (viaParent : Bool) : IO :=
  withParent viaParent (useOf WF2 14 ((Res.make (code 0) (code 1)).flatMap (code 4)))

theorem flat_private : Private WF2 [code 0, code 2] [code 1, code 3] [code 4] [cA, cB] := by
  refine ⟨fun k a r hk hb => ?_, fun k hk => ?_, fun k a q hk hq => ?_, fun c r hc h => ?_⟩
  · have h4 : k ≠ code 4 := by simpa using hk
    simp [WF2, W, renv, h4] at hb
  · have h0 : k ≠ code 0 := by simp at hk; exact hk.1
    have h2 : k ≠ code 2 := by simp at hk; exact hk.2
    simp only [WF2, W, renv, beq_iff_eq, h0, h2, ite_false, Bool.true_and]; decide +kernel
  · have h1 : k ≠ code 1 := by simp at hk; exact hk.1
    have h3 : k ≠ code 3 := by simp at hk; exact hk.2
    simp [WF2, W, renv, h1, h3] at hq; subst hq; rfl
  · have hA : c ≠ cA := by simp at hc; exact hc.1
    have hB : c ≠ cB := by simp at hc; exact hc.2
    simp [WF2, W, hA, hB] at h

theorem flat_sat (viaParent : Bool) :
    MarkedMake WF2 cA (code 0) (code 1) (.pure .unit) tagA tagRA ∧
    MarkedMake WF2 cB (code 2) (code 3) (.pure .unit) tagB tagRB ∧
    (∀ x, WF2.r.bind (code 4) x = .ok (Res.make (code 2) (code 3))) ∧
    Private WF2 [code 0, code 2] [code 1, code 3] [code 4] [cA, cB] ∧
    WellFormed libH [] (envH WF2 (bodyFlat viaParent)) harness ∧
    ∃ o, outcomesP {} counterMaskModel (envH WF2 (bodyFlat viaParent)) harness o ∧
      (∃ oc, o.summary = .done oc) ∧ logOf o = [tagA, tagB, tagRB, tagRA] := by
  refine ⟨markedA _ _ _, markedB _ _, fun _ => by simp [WF2, W, renv],
    flat_private, wellFormed _ _ _ _, ?_⟩
  cases viaParent
  · obtain ⟨o, ho, hs, hl⟩ := obs_of_run (env := envH WF2 (bodyFlat false)) (fuel := 8000) (cs := [])
      (p := harness) (s := .done (.succeeded .unit)) (l := [tagA, tagB, tagRB, tagRA]) (by decide +kernel)
    exact ⟨o, ho, ⟨_, hs⟩, hl⟩
  · obtain ⟨o, ho, hs, hl⟩ := obs_of_run (env := envH WF2 (bodyFlat true)) (fuel := 8000) (cs := parentSched)
      (p := harness) (s := .done (.succeeded (.ocSucceeded .unit))) (l := [tagA, tagB, tagRB, tagRA])
      (by decide +kernel)
    exact ⟨o, ho, ⟨_, hs⟩, hl⟩

end CatsEffectInLean.Proofs.Phase6.ResourceWitness
