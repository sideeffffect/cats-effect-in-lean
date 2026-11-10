import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedFamily

/-!
# Fixed-twin check of CE-0002: v3.7.1 on the same domain

The domain and the method: `ResourceEvalFixedFamily.lean`. One `decide +kernel` per program
`g` of `gFamily`. v3.7.1 fails the equation (`checkNotEqvP`: both outcome sets exact and
different) for the three programs with a self-cancel, and satisfies it (`checkEqvP`) for the
other six. So, on this domain, the statement fails exactly where the bug is.
-/

namespace CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource

/-- The v3.7.1 equation fails for `g` (exact and different outcome sets). -/
abbrev oldFails (g : IO) : Bool :=
  checkNotEqvP {} counterMaskModel (env g) bound allocOld (.uncancelable (uid 2))

/-- The v3.7.1 equation holds for `g` (exact and equal outcome sets). -/
abbrev oldHolds (g : IO) : Bool :=
  checkEqvP {} counterMaskModel (env g) bound allocOld (.uncancelable (uid 2))

theorem old_canceled : oldFails (gFamily.getD 0 .canceled) = true := by decide +kernel

theorem old_emit : oldHolds (gFamily.getD 1 .canceled) = true := by decide +kernel

theorem old_error : oldHolds (gFamily.getD 2 .canceled) = true := by decide +kernel

theorem old_canceledThenEmit : oldFails (gFamily.getD 3 .canceled) = true := by decide +kernel

theorem old_childEmit : oldHolds (gFamily.getD 4 .canceled) = true := by decide +kernel

theorem old_childCancel : oldHolds (gFamily.getD 5 .canceled) = true := by decide +kernel

theorem old_childJoin : oldHolds (gFamily.getD 6 .canceled) = true := by decide +kernel

theorem old_childCanceled : oldFails (gFamily.getD 7 .canceled) = true := by decide +kernel

theorem old_childEmitEmit : oldHolds (gFamily.getD 8 .canceled) = true := by decide +kernel

/-- v3.7.1 fails the equation for `g = IO.canceled` (the CE-0002 witness). -/
theorem v371_fails :
    ¬ EqvP {} counterMaskModel (env .canceled) allocOld (.uncancelable (uid 2)) :=
  not_eqvP_of_checkNotEqvP {} counterMaskModel (env .canceled) old_canceled

/-- v3.7.1 also fails it for `IO.canceled >> emit 1` and `start(emit 9) >> IO.canceled`. -/
theorem v371_fails_more :
    ¬ EqvP {} counterMaskModel (env (gFamily.getD 3 .canceled)) allocOld (.uncancelable (uid 2)) ∧
    ¬ EqvP {} counterMaskModel (env (gFamily.getD 7 .canceled)) allocOld (.uncancelable (uid 2)) :=
  ⟨not_eqvP_of_checkNotEqvP {} counterMaskModel _ old_canceledThenEmit,
   not_eqvP_of_checkNotEqvP {} counterMaskModel _ old_childCanceled⟩

end CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed
