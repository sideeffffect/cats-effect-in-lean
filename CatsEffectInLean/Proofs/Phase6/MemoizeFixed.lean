import CatsEffectInLean.Proofs.Phase6.MemoizeStuck

/-!
# CE-0030: fixed-twin check (decision 39)

Variant 1 of the `memoize` mirror (`Model/Memoize.lean`) is **not Cats Effect code**: the
`Finished` case of `flatModifyFull` returns `poll(fromEither(result).flatten)`. On the witness
program of `Proofs/Phase6/MemoizeStuck.lean` (`fa = IO.canceled`, two `get` fibers), with one
preemption at any position below 120 and FIFO after it, the twin is never blocked, and v3.7.1 is
blocked exactly at positions 35, 36 and 37.

In `lean_lib TwinChecks` (240 runs of about 80 micro-steps by `decide +kernel`; built by
`scripts/check_twin_checks.sh`).
-/

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

/-- One preemption at position `i` (then FIFO). -/
def onePreempt (variant i : Nat) : Option Summary :=
  (run fa u 120 (List.replicate i (.pick 0) ++ [.preempt]) (twoGets variant)).halt

/-- The fixed twin is never blocked with one preemption at a position below 120. -/
theorem fixed_onePreempt :
    (List.range 120).all (fun i => onePreempt 1 i != some .blocked) = true := by decide +kernel

/-- v3.7.1 is blocked exactly at positions 35, 36, 37 (positions below 120). -/
theorem old_onePreempt :
    (List.range 120).filter (fun i => onePreempt 0 i == some .blocked) = [35, 36, 37] := by
  decide +kernel

/-- All checks of this file (for the axiom check of `scripts/check_twin_checks.sh`). -/
theorem all_checks :
    (List.range 120).all (fun i => onePreempt 1 i != some .blocked) = true ∧
    (List.range 120).filter (fun i => onePreempt 0 i == some .blocked) = [35, 36, 37] :=
  ⟨fixed_onePreempt, old_onePreempt⟩

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
