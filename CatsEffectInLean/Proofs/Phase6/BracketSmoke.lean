import CatsEffectInLean.Proofs.Phase6.BracketSmokeDefs
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.Law03
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.Law23
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.Law13
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.Law33
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.Law53
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.Law73
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.Law83
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.Law04
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.Law24
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.Law14
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.Law54
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.Law84
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.Law95
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.Law88
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.LawWrongfunction
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.TwinPureC7
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.TwinPureC2
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.TwinPureU5
import CatsEffectInLean.Proofs.Phase6.BracketSmokeParts.TwinPureU8


/-!
# Smoke tests of the `guarantee`/`bracket` properties (Phase 6, track G)

Not registered. Exact outcome sets (`EqvP`, `exploreP`, `decide +kernel`) on concrete programs
of `Model/BracketExamples.lean`. Each check is one module in `BracketSmokeParts/` (memory; a
parallel CI matrix); this module collects them.
They support the `open` entries; they prove nothing for all programs.

* `guaranteeIsGuaranteeCase`: holds for 14 pairs `(fa, fin)`; a broken `guarantee` that never
  runs the finalizer breaks it (`law_wrongFunction`).
* `bracketFullIsKernelDefaultPureUse`: holds for 4 pure `use` functions with a self-cancel in
  acquire (the CE-0005 situation) and without it.
* `bracketReleaseOnce`, `guaranteeFinalizerOnce`: see `Proofs/Phase6/BracketWitness.lean`
  (satisfiability witnesses, kernel-checked) and `test/Phase6/BracketSmokeParent.lean`
  (`#guard` smoke tests on the harness, which evaluate the hypotheses too).
-/

namespace CatsEffectInLean.Proofs.Phase6.BracketSmoke

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Bracket
open CatsEffectInLean.Model.BracketExamples
open CatsEffectInLean.Props.Phase6.Bracket

/-- All checks of this module, for the axiom check of `scripts/check_twin_checks.sh`. -/
theorem all_checks : True := by
  have _ := @law_0_3
  have _ := @law_2_3
  have _ := @law_1_3
  have _ := @law_3_3
  have _ := @law_5_3
  have _ := @law_7_3
  have _ := @law_8_3
  have _ := @law_0_4
  have _ := @law_2_4
  have _ := @law_1_4
  have _ := @law_5_4
  have _ := @law_8_4
  have _ := @law_9_5
  have _ := @law_8_8
  have _ := @law_wrongFunction
  have _ := @twin_pure_c_7
  have _ := @twin_pure_c_2
  have _ := @twin_pure_u_5
  have _ := @twin_pure_u_8
  trivial

end CatsEffectInLean.Proofs.Phase6.BracketSmoke
