import CatsEffectInLean.Props.Calibration.SyncStep

/-!
# A finite check for `StepIdentityFor` (CE-0001, CE-0004, fixed twins)

`StepIdentityFor stepped env fa refs` (`Props/Calibration/SyncStep.lean`) quantifies over all
step-only schedules and all `SyncIO` fuels. For one concrete program it follows from finite
facts that `decide +kernel` can check:

* The `SyncIO` part is out of fuel (no claim) for each fuel below `F`, and gives the same rest
  `(p, h)` for each fuel `m + F` (`rfl` with a free `m`).
* A finite state list of the direct run holds the start state and is closed under both `step`
  choices; each claim state in it has the erased observation `o`. The same for the stepped run
  from the root fiber of `p` on heap `h`.
* One schedule of each side gives a claim with observation `o`.

Then both sides make the same claims (`stepIdentity_of_check`). For a refutation, the stepped
list has no claim state with the direct observation (`not_stepIdentity_of_check`).
-/

namespace CatsEffectInLean.Proofs.Calibration.StepCheck

open CatsEffectInLean.Model
open CatsEffectInLean.Model.SyncStepObs
open CatsEffectInLean.Props.Calibration

/-- A state of the single-fiber driver (`IOFiber` mirror with `counterMaskModel`). -/
abbrev S := Solo CounterMask

/-- One choice. -/
def nx (env : UserEnv) (c : SoloChoice) (s : S) : S := Solo.next {} counterMaskModel env c s

/-- `reach` is closed under both `step` choices. -/
def closed (env : UserEnv) (reach : List S) : Bool :=
  reach.all fun s => reach.contains (nx env (.step true) s) && reach.contains (nx env (.step false) s)

/-- Each claim state of `reach` has the erased observation `o`. -/
def claimsAre (reach : List S) (o : Obs) : Bool :=
  reach.all fun s => !isClaim (ofSolo s).1 || decide (eraseObs (ofSolo s) = o)

/-- No claim state of `reach` has the erased observation `o`. -/
def claimsAvoid (reach : List S) (o : Obs) : Bool :=
  reach.all fun s => !isClaim (ofSolo s).1 || decide (eraseObs (ofSolo s) ≠ o)

/-- Does a `SyncIO` result make a claim? -/
def restClaims : Except Summary (IO × Heap) → Bool
  | .error s => isClaim s
  | .ok _ => true

/-- Breadth-first growth of a state list (no duplicates). -/
def grow (env : UserEnv) : Nat → List S → List S
  | 0, l => l
  | n + 1, l =>
    grow env n (l.foldl (fun acc s => [nx env (.step true) s, nx env (.step false) s].foldl
      (fun acc t => if acc.contains t then acc else acc ++ [t]) acc) l)

theorem exec_mem (env : UserEnv) (reach : List S) (hc : closed env reach = true) :
    ∀ (bs : List Bool) (s : S), s ∈ reach →
      Solo.exec {} counterMaskModel env (steps bs) s ∈ reach
  | [], _, hs => hs
  | b :: bs, s, hs => by
    have h := List.all_eq_true.mp hc s hs
    simp only [Bool.and_eq_true, List.contains_iff_mem] at h
    refine exec_mem env reach hc bs _ ?_
    cases b
    · exact h.2
    · exact h.1

theorem isClaim_erase (o : Obs) : isClaim (eraseObs o).1 = isClaim o.1 := by
  obtain ⟨s, r, out⟩ := o
  cases s <;> rfl

theorem obsOfRest_error (env : UserEnv) (refs : List Val) (s : Summary) (cs : List SoloChoice) :
    obsOfRest env refs (.error s) cs = (s, refs, []) := rfl

/-- The finite check gives both directions of `<->`. -/
theorem stepIdentity_of_check (env : UserEnv) (fa : IO) (refs : List Val)
    (R : Nat → Except Summary (IO × Heap)) (F : Nat) (p : IO) (h : Heap) (o : Obs)
    (reachD reachS : List S) (nD nS : Nat)
    (hsmall : ∀ k, k < F → restClaims (R k) = false)
    (hbig : ∀ m, R (m + F) = .ok (p, h))
    (hD : Solo.init counterMaskModel fa refs ∈ reachD) (hDc : closed env reachD = true)
    (hDo : claimsAre reachD o = true)
    (hS : rootOn counterMaskModel p h ∈ reachS) (hSc : closed env reachS = true)
    (hSo : claimsAre reachS o = true)
    (hDw : isClaim (directObs env fa refs (steps (List.replicate nD true))).1 = true ∧
      eraseObs (directObs env fa refs (steps (List.replicate nD true))) = o)
    (hSw : isClaim (obsOfRest env refs (.ok (p, h)) (steps (List.replicate nS true))).1 = true ∧
      eraseObs (obsOfRest env refs (.ok (p, h)) (steps (List.replicate nS true))) = o) :
    StepIdentityFor (fun fuel cs => obsOfRest env refs (R fuel) cs) env fa refs := by
  have hDall : ∀ bs, isClaim (directObs env fa refs (steps bs)).1 = true →
      eraseObs (directObs env fa refs (steps bs)) = o := by
    intro bs hcl
    have hm := exec_mem env reachD hDc bs _ hD
    have := List.all_eq_true.mp hDo _ hm
    simp only [directObs] at hcl ⊢
    simp_all
  have hSall : ∀ bs, isClaim (obsOfRest env refs (.ok (p, h)) (steps bs)).1 = true →
      eraseObs (obsOfRest env refs (.ok (p, h)) (steps bs)) = o := by
    intro bs hcl
    have hm := exec_mem env reachS hSc bs _ hS
    have := List.all_eq_true.mp hSo _ hm
    simp only [obsOfRest] at hcl ⊢
    simp_all
  refine ⟨fun bs hcl => ⟨F, List.replicate nS true, ?_⟩, fun fuel bs hcl => ?_⟩
  · have := hbig 0
    rw [Nat.zero_add] at this
    simp only [this]
    rw [hSw.2, hDall bs hcl]
  · by_cases hf : fuel < F
    · have hs := hsmall fuel hf
      cases hr : R fuel with
      | error s =>
        simp only [hr, obsOfRest_error] at hcl
        simp [restClaims, hr] at hs
        simp [hs] at hcl
      | ok r => simp [restClaims, hr] at hs
    · obtain ⟨m, rfl⟩ : ∃ m, fuel = m + F := ⟨fuel - F, by omega⟩
      simp only [hbig] at hcl ⊢
      exact ⟨List.replicate nD true, by rw [hDw.2, hSall bs hcl]⟩

/-- The finite check of a refutation: a direct claim whose observation no stepped run gives. -/
theorem not_stepIdentity_of_check (env : UserEnv) (fa : IO) (refs : List Val)
    (R : Nat → Except Summary (IO × Heap)) (F : Nat) (p : IO) (h : Heap) (oD : Obs)
    (reachS : List S) (nD : Nat)
    (hsmall : ∀ k, k < F → restClaims (R k) = false)
    (hbig : ∀ m, R (m + F) = .ok (p, h))
    (hS : rootOn counterMaskModel p h ∈ reachS) (hSc : closed env reachS = true)
    (hSo : claimsAvoid reachS oD = true)
    (hDw : isClaim (directObs env fa refs (steps (List.replicate nD true))).1 = true ∧
      eraseObs (directObs env fa refs (steps (List.replicate nD true))) = oD) :
    ¬ StepIdentityFor (fun fuel cs => obsOfRest env refs (R fuel) cs) env fa refs := by
  intro hid
  obtain ⟨fuel, bs, heq⟩ := hid.1 (List.replicate nD true) hDw.1
  rw [hDw.2] at heq
  have hcl : isClaim (obsOfRest env refs (R fuel) (steps bs)).1 = true := by
    rw [← isClaim_erase, heq]
    have := hDw.1
    rw [← isClaim_erase, hDw.2] at this
    exact this
  by_cases hf : fuel < F
  · have hs := hsmall fuel hf
    cases hr : R fuel with
    | error s =>
      simp only [hr, obsOfRest_error] at hcl
      simp [restClaims, hr] at hs
      simp [hs] at hcl
    | ok r => simp [restClaims, hr] at hs
  · obtain ⟨m, rfl⟩ : ∃ m, fuel = m + F := ⟨fuel - F, by omega⟩
    simp only [hbig] at hcl heq
    have hm := exec_mem env reachS hSc bs _ hS
    have := List.all_eq_true.mp hSo _ hm
    simp only [obsOfRest] at hcl heq
    simp_all

end CatsEffectInLean.Proofs.Calibration.StepCheck
