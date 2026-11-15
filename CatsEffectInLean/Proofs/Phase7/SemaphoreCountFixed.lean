import CatsEffectInLean.Proofs.Phase7.SemaphoreCountFixedDefs
import CatsEffectInLean.Proofs.Phase7.SemaphoreCount

/-!
# CE-0060 fixed-twin check (decision 39; `TwinChecks`)

The fixed twin (`fixedEnv`, `SemaphoreCountFixedDefs.lean`) meets the conclusion of
`semCountAtRest` (`count = available` when every user fiber has ended) on a small family of
inputs, for the schedules with no preemption or one preemption at step 8, 16, ..., 88 (otherwise
`pick 0`);
v3.7.1 does not (the default schedule of `countRoot`, `SemaphoreCount.lean`). The family: `k ∈ {0,
1}`, two `acqRel 1` fibers (the waiters), and the parent acts: cancel both in either order, after two
cedes or one. Supporting evidence for the bug record, not a registered property. The random smoke
test (`lake exe semsmoke`) also runs the twin on random inputs.
-/

namespace CatsEffectInLean.Proofs.Phase7

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase7.Semaphore

/-- The claim of `semCountAtRest` on one observation (stopped runs only). -/
def countClaim (o : Option Obs) : Bool :=
  match o with
  | some o =>
    match o.summary with
    | .done (.succeeded v) =>
      match availOf v, countOf v with
      | some a, some c => c == (a : Int)
      | _, _ => false
    | _ => true
  | none => true

/-- The schedule with one preemption at step `p` (`p = 0`: none). -/
def onePreempt (p : Nat) : List PChoice :=
  if p == 0 then [] else (List.replicate (p - 1) (.pick 0)) ++ [.preempt]

def fixRoot (k : Nat) (as : List Act) : IO := lockRoot (.sem k) (countBus.map BUse.toUse) as

/-- The preemption points: no preemption, then every 8th step up to 88 (the run of the default
schedule has 92 steps). -/
def fixPoints : List Nat := [0, 8, 16, 24, 32, 40, 48, 56, 64, 72, 80, 88]

/-- One input of the family on all `fixPoints` schedules, fuel 400 (every run stops before). -/
def fixCheck (k : Nat) (as : List Act) : Bool :=
  fixPoints.all fun p =>
    countClaim (runObsP {} counterMaskModel (fixedEnv (env behaved)) 400 (onePreempt p) (fixRoot k as))

theorem fixed_count_0 : fixCheck 0 [.cede, .cede, .cancel 1, .cancel 0] = true := by decide +kernel
theorem fixed_count_1 : fixCheck 0 [.cede, .cede, .cancel 0, .cancel 1] = true := by decide +kernel
theorem fixed_count_2 : fixCheck 0 [.cede, .cancel 1, .cancel 0] = true := by decide +kernel
theorem fixed_count_3 : fixCheck 1 [.cede, .cede, .cancel 1, .cancel 0] = true := by decide +kernel

/-- v3.7.1 breaks the claim on the first input of the family (the default schedule). -/
theorem old_count_fails :
    countClaim (runObsP {} counterMaskModel (env behaved) 400 [] (fixRoot 0 [.cede, .cede, .cancel 1, .cancel 0])) = false := by
  decide +kernel

/-- All checks of this module (the result theorem of `scripts/check_twin_checks.sh`). -/
theorem SemaphoreCountFixed.all_checks :
    fixCheck 0 [.cede, .cede, .cancel 1, .cancel 0] = true ∧ fixCheck 0 [.cede, .cede, .cancel 0, .cancel 1] = true ∧
    fixCheck 0 [.cede, .cancel 1, .cancel 0] = true ∧ fixCheck 1 [.cede, .cede, .cancel 1, .cancel 0] = true ∧
    countClaim (runObsP {} counterMaskModel (env behaved) 400 [] (fixRoot 0 [.cede, .cede, .cancel 1, .cancel 0])) = false :=
  ⟨fixed_count_0, fixed_count_1, fixed_count_2, fixed_count_3, old_count_fails⟩

end CatsEffectInLean.Proofs.Phase7
