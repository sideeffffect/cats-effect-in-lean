import CatsEffectInLean.Proofs.Phase6.ResourceWitness

/-!
# Wrong-function tests of `useReleaseOnce` and `flatMapReleaseOrder` (review batch 9)

On the witness inputs (`ResourceWitnessEnv.W`, the same harness), a broken implementation breaks
each conclusion in a run that ends with a root outcome (kernel-checked runs, FIFO schedule). So the
conclusions are not satisfied by every implementation.

* `use` without release (`acquire.flatMap(f)`, not Cats Effect code): the log is `[A]`, so the
  release tag count `0 ≠ 1` (`useReleaseOnce` fails).
* `flatMap` that releases the outer resource first (FIFO), modelled by the reversed nesting
  `make(B).flatMap(_ => make(A))` under the mirror: the log is `[B, A, RA, RB]`, so `RB` is not
  before `RA` (`flatMapReleaseOrder` fails).
-/

namespace CatsEffectInLean.Proofs.Phase6.ResourceWrongFunction

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceUse
open CatsEffectInLean.Props.Phase6.Resource
open CatsEffectInLean.Proofs.Phase6.ResourceWitnessEnv
open CatsEffectInLean.Proofs.Phase6.ResourceWitness

/-! ## `use` without release -/

/-- `acquire.flatMap(f)` with the marked acquire of `A` and the witness `f = 14` (`_ => IO.unit`). -/
def noReleaseUse : IO := .flatMap (WU.r.acquire (code 0)) (uid 7)

theorem noReleaseUse_breaks :
    ∃ o, outcomesP {} counterMaskModel (envH WU noReleaseUse) harness o ∧
      (∃ oc, o.summary = .done oc) ∧ (logOf o).count tagRA ≠ (logOf o).count tagA := by
  obtain ⟨o, ho, hs, hl⟩ := obs_of_run (env := envH WU noReleaseUse) (fuel := 8000) (cs := [])
    (p := harness) (s := .done (.succeeded .unit)) (l := [tagA]) (by decide +kernel)
  exact ⟨o, ho, ⟨_, hs⟩, by rw [hl]; decide⟩

/-! ## `flatMap` that releases the outer resource first -/

/-- `W` with one more `Bind` entry: `code 5` gives `make(A)`. -/
def WR : UEnv :=
  { r := { (W false true true).r with
           bind := fun k x => if k == code 5 then .ok (Res.make (code 0) (code 1)) else (W false true true).r.bind k x }
    resOf := (W false true true).resOf }

def fifoBody : IO := useOf WR 14 ((Res.make (code 2) (code 3)).flatMap (code 5))

theorem fifo_breaks :
    ∃ o, outcomesP {} counterMaskModel (envH WR fifoBody) harness o ∧
      (∃ oc, o.summary = .done oc) ∧ ¬ (tagRA ∈ logOf o → tagRB ∈ logOf o → Before (logOf o) tagRB tagRA) := by
  obtain ⟨o, ho, hs, hl⟩ := obs_of_run (env := envH WR fifoBody) (fuel := 8000) (cs := [])
    (p := harness) (s := .done (.succeeded .unit)) (l := [tagB, tagA, tagRA, tagRB]) (by decide +kernel)
  refine ⟨o, ho, ⟨_, hs⟩, ?_⟩
  rw [hl]
  unfold Before
  decide

end CatsEffectInLean.Proofs.Phase6.ResourceWrongFunction
