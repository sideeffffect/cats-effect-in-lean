import CatsEffectInLean.Proofs.Phase6.ResourceBoth

/-! Definitions of the CE-0020 fixed-twin check (`ResourceBothFixed.lean`); the checks are in
`ResourceBothFixedParts/`, one module each, so that each Lean process stays well under the
12 GB budget of a 16 GB CI runner. -/

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
  | .done _ => (logOf o).count tagRA == (logOf o).count tagA && (logOf o).count tagRB == (logOf o).count tagB
  | _ => true

/-- The run of the harness with test body `b` on schedule `cs` satisfies the conclusion. -/
def okOn (b : IO) (cs : List PChoice) : Bool :=
  match runObsP {} counterMaskModel (envH WB b) 8000 cs harness with
  | some o => concl o
  | none => true

end CatsEffectInLean.Proofs.Phase6.ResourceBothFixed
