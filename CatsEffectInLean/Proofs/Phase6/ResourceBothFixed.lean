import CatsEffectInLean.Proofs.Phase6.ResourceBothFixedDefs
import CatsEffectInLean.Proofs.Phase6.ResourceBothFixedParts.Fixed_0
import CatsEffectInLean.Proofs.Phase6.ResourceBothFixedParts.Fixed_1
import CatsEffectInLean.Proofs.Phase6.ResourceBothFixedParts.Fixed_2
import CatsEffectInLean.Proofs.Phase6.ResourceBothFixedParts.Fixed_3
import CatsEffectInLean.Proofs.Phase6.ResourceBothFixedParts.Fixed_4
import CatsEffectInLean.Proofs.Phase6.ResourceBothFixedParts.Fixed_5
import CatsEffectInLean.Proofs.Phase6.ResourceBothFixedParts.Fixed_6
import CatsEffectInLean.Proofs.Phase6.ResourceBothFixedParts.Fixed_7
import CatsEffectInLean.Proofs.Phase6.ResourceBothFixedParts.Fixed_8
import CatsEffectInLean.Proofs.Phase6.ResourceBothFixedParts.Fixed_9
import CatsEffectInLean.Proofs.Phase6.ResourceBothFixedParts.Fixed_10
import CatsEffectInLean.Proofs.Phase6.ResourceBothFixedParts.Fixed_11
import CatsEffectInLean.Proofs.Phase6.ResourceBothFixedParts.Old

/-!
# Fixed-twin check of CE-0020 (decision 39), kernel-checked

Input: the refutation witness of `bothReleasesBoth` (`ResourceBothWitness`: environment
`W true true false`, all hypotheses of `BothReleasesBothFor` proven there (`Private` and the deep `WellFormed` too); they do not depend on
the implementation of `both`). Domain: the 120 schedules "FIFO for `k` choices, then `pick d`"
(`63 ≤ k < 123`, `d ∈ {1, 2}`; the release phase of the program, where v3.7.1 fails at `k = 92`),
fuel 8000. (About 6 s of kernel time per run; the full 600-schedule family and 1,500 random
schedules are `#guard`ed in `test/Phase6/ResourceSmoke.lean`.)

* `fixed_satisfies`: for the fixed twin `fixedBothRes` (not Cats Effect code), every run of the
  domain that ends with a root outcome satisfies the conclusion of the statement (each release as
  often as its acquire).
* `old_violates`: v3.7.1 (`bothRes`) has a run in the domain that violates it.

So the statement separates v3.7.1 from the fix on this domain. Not checked: all schedules (the
exact `outcomesP` set of this program is too large for `outcomesPList`). In `lean_lib TwinChecks`
built by `scripts/check_twin_checks.sh`. The 60 checks (one per `k`, 2 schedules each; 12 modules of 5) and the v3.7.1 run are
one module each (`ResourceBothFixedParts/`), so each Lean process stays under 12 GB.
-/

namespace CatsEffectInLean.Proofs.Phase6.ResourceBothFixed

open CatsEffectInLean.Model
open CatsEffectInLean.Model.ResourceUse
open CatsEffectInLean.Props.Phase6.Resource
open CatsEffectInLean.Proofs.Phase6.ResourceWitnessEnv
open CatsEffectInLean.Proofs.Phase6.ResourceBothWitness

theorem fixed_satisfies : ∀ cs ∈ family 63 60, okOn fixedBody cs = true := by
  have hall : ∀ i, i < 60 → (family (63 + i) 1).all (okOn fixedBody) = true := by
    intro i hi
    match i, hi with
    | 0, _ => exact fixed_k63 | 1, _ => exact fixed_k64 | 2, _ => exact fixed_k65 | 3, _ => exact fixed_k66
    | 4, _ => exact fixed_k67 | 5, _ => exact fixed_k68 | 6, _ => exact fixed_k69 | 7, _ => exact fixed_k70
    | 8, _ => exact fixed_k71 | 9, _ => exact fixed_k72 | 10, _ => exact fixed_k73 | 11, _ => exact fixed_k74
    | 12, _ => exact fixed_k75 | 13, _ => exact fixed_k76 | 14, _ => exact fixed_k77 | 15, _ => exact fixed_k78
    | 16, _ => exact fixed_k79 | 17, _ => exact fixed_k80 | 18, _ => exact fixed_k81 | 19, _ => exact fixed_k82
    | 20, _ => exact fixed_k83 | 21, _ => exact fixed_k84 | 22, _ => exact fixed_k85 | 23, _ => exact fixed_k86
    | 24, _ => exact fixed_k87 | 25, _ => exact fixed_k88 | 26, _ => exact fixed_k89 | 27, _ => exact fixed_k90
    | 28, _ => exact fixed_k91 | 29, _ => exact fixed_k92 | 30, _ => exact fixed_k93 | 31, _ => exact fixed_k94
    | 32, _ => exact fixed_k95 | 33, _ => exact fixed_k96 | 34, _ => exact fixed_k97 | 35, _ => exact fixed_k98
    | 36, _ => exact fixed_k99 | 37, _ => exact fixed_k100 | 38, _ => exact fixed_k101 | 39, _ => exact fixed_k102
    | 40, _ => exact fixed_k103 | 41, _ => exact fixed_k104 | 42, _ => exact fixed_k105 | 43, _ => exact fixed_k106
    | 44, _ => exact fixed_k107 | 45, _ => exact fixed_k108 | 46, _ => exact fixed_k109 | 47, _ => exact fixed_k110
    | 48, _ => exact fixed_k111 | 49, _ => exact fixed_k112 | 50, _ => exact fixed_k113 | 51, _ => exact fixed_k114
    | 52, _ => exact fixed_k115 | 53, _ => exact fixed_k116 | 54, _ => exact fixed_k117 | 55, _ => exact fixed_k118
    | 56, _ => exact fixed_k119 | 57, _ => exact fixed_k120 | 58, _ => exact fixed_k121 | 59, _ => exact fixed_k122
    | _ + 60, h => exact absurd h (by omega)
  intro cs hcs
  simp only [family, List.mem_flatMap, List.mem_range] at hcs
  obtain ⟨i, hi, hm⟩ := hcs
  have h := hall i hi
  rw [List.all_eq_true] at h
  apply h
  simp only [family, List.mem_flatMap, List.mem_range]
  exact ⟨0, by omega, by simpa using hm⟩

theorem old_violates : ∃ cs ∈ family 63 60, okOn body cs = false :=
  ⟨sched, by
    simp only [family, List.mem_flatMap, List.mem_range]
    exact ⟨29, by omega, by simp [sched]⟩, old_sched⟩

/-- Everything of this module (for `#print axioms` in `scripts/check_twin_checks.sh`). -/
theorem all_checks : (∀ cs ∈ family 63 60, okOn fixedBody cs = true) ∧
    ∃ cs ∈ family 63 60, okOn body cs = false := ⟨fixed_satisfies, old_violates⟩

end CatsEffectInLean.Proofs.Phase6.ResourceBothFixed
