import CatsEffectInLean.Proofs.Calibration.ResourceEvalFixedFamily

/-!
# CE-0002 fixed-twin check: the per-program check functions

Shared by the per-program proof files in `ResourceEvalFixedParts/`. Each part file runs one
`decide +kernel`, so that one Lean process stays far below the CI runner memory (a single file
with all nine checks needed 13 GB; see `raw/project-decisions/2026-11-10-ci-memory-split-notes.md`).
-/

namespace CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceFixed

/-- The fixed-twin check for one `g`. -/
abbrev fixedCheck (g : IO) : Bool :=
  checkEqvP {} counterMaskModel (env g) bound (allocatedCaseFixed 0) (.uncancelable (uid 1))

/-- The v3.7.1 equation fails for `g` (exact and different outcome sets). -/
abbrev oldFails (g : IO) : Bool :=
  checkNotEqvP {} counterMaskModel (env g) bound allocOld (.uncancelable (uid 2))

/-- The v3.7.1 equation holds for `g` (exact and equal outcome sets). -/
abbrev oldHolds (g : IO) : Bool :=
  checkEqvP {} counterMaskModel (env g) bound allocOld (.uncancelable (uid 2))

end CatsEffectInLean.Proofs.Calibration.ResourceEvalFixed
