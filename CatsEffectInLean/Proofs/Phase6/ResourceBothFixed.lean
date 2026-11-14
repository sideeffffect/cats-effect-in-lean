import CatsEffectInLean.Proofs.Phase6.ResourceBoth

/-!
# Fixed-twin check of CE-0020 (decision 39), kernel-checked

Input: the refutation witness of `bothReleasesBoth` (`ResourceBothWitness`: environment
`W true true false`, all hypotheses of `BothReleasesBothFor` proven there; they do not depend on
the implementation of `both`). Domain: the 120 schedules "FIFO for `k` choices, then `pick d`"
(`60 ≤ k < 120`, `d ∈ {1, 2}`; the release phase of the program, where v3.7.1 fails at `k = 89`),
fuel 6000. (About 6 s of kernel time per run; the full 600-schedule family and 1,500 random
schedules are `#guard`ed in `test/Phase6/ResourceSmoke.lean`.)

* `fixed_satisfies`: for the fixed twin `fixedBothRes` (not Cats Effect code), every run of the
  domain that ends with a root outcome satisfies the conclusion of the statement (each release as
  often as its acquire).
* `old_violates`: v3.7.1 (`bothRes`) has a run in the domain that violates it.

So the statement separates v3.7.1 from the fix on this domain. Not checked: all schedules (the
exact `outcomesP` set of this program is too large for `outcomesPList`). In `lean_lib TwinChecks`
(about 15 minutes), built by `scripts/check_twin_checks.sh`.
-/

namespace CatsEffectInLean.Proofs.Phase6.ResourceBothFixed

open CatsEffectInLean.Model
open CatsEffectInLean.Model.ResourceUse
open CatsEffectInLean.Props.Phase6.Resource
open CatsEffectInLean.Proofs.Phase6.ResourceWitnessEnv
open CatsEffectInLean.Proofs.Phase6.ResourceBothWitness

/-- Schedules `k ∈ [lo, lo + n)`. -/
def family (lo n : Nat) : List (List PChoice) :=
  (List.range n).flatMap fun i => [1, 2].map fun d => List.replicate (lo + i) (PChoice.pick 0) ++ [.pick d]

/-- The conclusion of `bothReleasesBoth` on one run (runs without a root outcome are not counted). -/
def concl (o : Obs) : Bool :=
  match o.summary with
  | .done _ => o.out.count RA == o.out.count A && o.out.count RB == o.out.count B
  | _ => true

def okOn (p : IO) (cs : List PChoice) : Bool :=
  match runObsP {} counterMaskModel (envH WB) 6000 cs p with
  | some o => concl o
  | none => true

set_option maxHeartbeats 0 in
theorem fixed_0 : (family 60 5).all (okOn fixedProg) = true := by decide +kernel
set_option maxHeartbeats 0 in
theorem fixed_1 : (family 65 5).all (okOn fixedProg) = true := by decide +kernel
set_option maxHeartbeats 0 in
theorem fixed_2 : (family 70 5).all (okOn fixedProg) = true := by decide +kernel
set_option maxHeartbeats 0 in
theorem fixed_3 : (family 75 5).all (okOn fixedProg) = true := by decide +kernel
set_option maxHeartbeats 0 in
theorem fixed_4 : (family 80 5).all (okOn fixedProg) = true := by decide +kernel
set_option maxHeartbeats 0 in
theorem fixed_5 : (family 85 5).all (okOn fixedProg) = true := by decide +kernel
set_option maxHeartbeats 0 in
theorem fixed_6 : (family 90 5).all (okOn fixedProg) = true := by decide +kernel
set_option maxHeartbeats 0 in
theorem fixed_7 : (family 95 5).all (okOn fixedProg) = true := by decide +kernel
set_option maxHeartbeats 0 in
theorem fixed_8 : (family 100 5).all (okOn fixedProg) = true := by decide +kernel
set_option maxHeartbeats 0 in
theorem fixed_9 : (family 105 5).all (okOn fixedProg) = true := by decide +kernel
set_option maxHeartbeats 0 in
theorem fixed_10 : (family 110 5).all (okOn fixedProg) = true := by decide +kernel
set_option maxHeartbeats 0 in
theorem fixed_11 : (family 115 5).all (okOn fixedProg) = true := by decide +kernel

theorem fixed_satisfies : ∀ cs ∈ family 60 60, okOn fixedProg cs = true := by
  have hall : ∀ n, n < 12 → (family (60 + 5 * n) 5).all (okOn fixedProg) = true := by
    intro n hn
    match n, hn with
    | 0, _ => exact fixed_0 | 1, _ => exact fixed_1 | 2, _ => exact fixed_2 | 3, _ => exact fixed_3
    | 4, _ => exact fixed_4 | 5, _ => exact fixed_5 | 6, _ => exact fixed_6 | 7, _ => exact fixed_7
    | 8, _ => exact fixed_8 | 9, _ => exact fixed_9 | 10, _ => exact fixed_10 | 11, _ => exact fixed_11
  intro cs hcs
  simp only [family, List.mem_flatMap, List.mem_range] at hcs
  obtain ⟨i, hi, hm⟩ := hcs
  have h := hall (i / 5) (by omega)
  rw [List.all_eq_true] at h
  apply h
  simp only [family, List.mem_flatMap, List.mem_range]
  exact ⟨i % 5, Nat.mod_lt _ (by omega), by rw [show 60 + 5 * (i / 5) + i % 5 = 60 + i by omega]; exact hm⟩

theorem old_violates : ∃ cs ∈ family 60 60, okOn (withParent false prog) cs = false :=
  ⟨sched, by
    simp only [family, List.mem_flatMap, List.mem_range]
    exact ⟨29, by omega, by simp [sched]⟩, by decide +kernel⟩

/-- Everything of this module (for `#print axioms` in `scripts/check_twin_checks.sh`). -/
theorem all_checks : (∀ cs ∈ family 60 60, okOn fixedProg cs = true) ∧
    ∃ cs ∈ family 60 60, okOn (withParent false prog) cs = false := ⟨fixed_satisfies, old_violates⟩

end CatsEffectInLean.Proofs.Phase6.ResourceBothFixed
