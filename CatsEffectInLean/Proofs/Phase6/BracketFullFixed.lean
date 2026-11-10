import CatsEffectInLean.Proofs.Phase6.BracketFullTwin

/-!
# Fixed-twin check of CE-0005 (decision 39)

Supporting evidence, not a registered property. `fixedBracketFullIO` is `IO.bracketFull` with
`poll(IO.defer(use(a)))` in place of `IO.defer(poll(use(a)))` (not Cats Effect code). On the
witness environment of `BracketFullTwin.lean` and the 8 programs
`acquire ∈ {IO.canceled, IO.unit}` × `use ∈ {throw E5, IO.unit, IO.canceled, IO.raiseError(E6)}`
(user ids `0`/`6` and `2`/`4`/`8`/`10`; release `IO.unit`, id `4`):

* the fixed twin is `EqvP` to the kernel body on all 8 (`fixed_*`);
* v3.7.1 `IO.bracketFull` is `EqvP` to the kernel body on 7 and differs on the witness
  (acquire `IO.canceled`, use throws), `old_*`.

So the twin statement separates the defect from the fix (wrong-function test of batch 2).
-/

namespace CatsEffectInLean.Proofs.Phase6.BracketFullFixed

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Bracket
open CatsEffectInLean.Proofs.Phase6.BracketFullWitness

theorem fixed_c_throw : checkEqvP {} counterMaskModel env 200 (fixedBracketFullIO 0 2 4) (defaultBracketFullIO 0 2 4) = true := by decide +kernel
theorem fixed_c_unit : checkEqvP {} counterMaskModel env 200 (fixedBracketFullIO 0 4 4) (defaultBracketFullIO 0 4 4) = true := by decide +kernel
theorem fixed_c_canceled : checkEqvP {} counterMaskModel env 200 (fixedBracketFullIO 0 8 4) (defaultBracketFullIO 0 8 4) = true := by decide +kernel
theorem fixed_c_raise : checkEqvP {} counterMaskModel env 200 (fixedBracketFullIO 0 10 4) (defaultBracketFullIO 0 10 4) = true := by decide +kernel
theorem fixed_u_throw : checkEqvP {} counterMaskModel env 200 (fixedBracketFullIO 6 2 4) (defaultBracketFullIO 6 2 4) = true := by decide +kernel
theorem fixed_u_unit : checkEqvP {} counterMaskModel env 200 (fixedBracketFullIO 6 4 4) (defaultBracketFullIO 6 4 4) = true := by decide +kernel
theorem fixed_u_canceled : checkEqvP {} counterMaskModel env 200 (fixedBracketFullIO 6 8 4) (defaultBracketFullIO 6 8 4) = true := by decide +kernel
theorem fixed_u_raise : checkEqvP {} counterMaskModel env 200 (fixedBracketFullIO 6 10 4) (defaultBracketFullIO 6 10 4) = true := by decide +kernel

theorem old_c_throw : checkNotEqvP {} counterMaskModel env 200 (bracketFullIO 0 2 4) (defaultBracketFullIO 0 2 4) = true := by decide +kernel
theorem old_c_unit : checkEqvP {} counterMaskModel env 200 (bracketFullIO 0 4 4) (defaultBracketFullIO 0 4 4) = true := by decide +kernel
theorem old_c_canceled : checkEqvP {} counterMaskModel env 200 (bracketFullIO 0 8 4) (defaultBracketFullIO 0 8 4) = true := by decide +kernel
theorem old_c_raise : checkEqvP {} counterMaskModel env 200 (bracketFullIO 0 10 4) (defaultBracketFullIO 0 10 4) = true := by decide +kernel
theorem old_u_throw : checkEqvP {} counterMaskModel env 200 (bracketFullIO 6 2 4) (defaultBracketFullIO 6 2 4) = true := by decide +kernel
theorem old_u_unit : checkEqvP {} counterMaskModel env 200 (bracketFullIO 6 4 4) (defaultBracketFullIO 6 4 4) = true := by decide +kernel
theorem old_u_canceled : checkEqvP {} counterMaskModel env 200 (bracketFullIO 6 8 4) (defaultBracketFullIO 6 8 4) = true := by decide +kernel
theorem old_u_raise : checkEqvP {} counterMaskModel env 200 (bracketFullIO 6 10 4) (defaultBracketFullIO 6 10 4) = true := by decide +kernel


/-- All checks of this module, for the axiom check of `scripts/check_twin_checks.sh`. -/
theorem all_checks : True := by
  have _ := @fixed_c_throw
  have _ := @fixed_c_unit
  have _ := @fixed_c_canceled
  have _ := @fixed_c_raise
  have _ := @fixed_u_throw
  have _ := @fixed_u_unit
  have _ := @fixed_u_canceled
  have _ := @fixed_u_raise
  have _ := @old_c_throw
  have _ := @old_c_unit
  have _ := @old_c_canceled
  have _ := @old_c_raise
  have _ := @old_u_throw
  have _ := @old_u_unit
  have _ := @old_u_canceled
  have _ := @old_u_raise
  trivial

end CatsEffectInLean.Proofs.Phase6.BracketFullFixed
