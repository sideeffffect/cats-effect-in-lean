import CatsEffectInLean.Proofs.Phase6.MemoizeFixedDefs
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.FixedOnePreempt
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.OldOnePreempt
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.FamFixedCanceled
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.FamOldCanceled
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.FamFixedPure
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.FamOldPure
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.FamFixedError
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.FamOldError
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.FamFixedEmitCanceled
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.FamOldEmitCanceled
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.FamFixedStartEmitCanceled
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.FamOldStartEmitCanceled
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.FamFixedCedeCanceled
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.FamOldCedeCanceled
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.FamFixedCedeCanceled2
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.FamOldCedeCanceled2
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.FamFixedUncCanceled
import CatsEffectInLean.Proofs.Phase6.MemoizeFixedParts.FamOldUncCanceled

/-! CE-0030 fixed-twin check (decision 39): the checks of `MemoizeFixedParts/` together
(definitions and the table: `MemoizeFixedDefs.lean`). -/

namespace CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase6.Memoize

/-- All checks of this file (for the axiom check of `scripts/check_twin_checks.sh`). -/
theorem all_checks :
    ((List.range 120).all (fun i => onePreempt 1 i != some .blocked) = true ∧
     (List.range 120).filter (fun i => onePreempt 0 i == some .blocked) = [35, 36, 37]) ∧
    (fixedOK .canceled ∧ fixedOK faPure ∧ fixedOK faError ∧ fixedOK faEmitCanceled ∧
     fixedOK faStartEmitCanceled ∧ fixedOK faCedeCanceled ∧ fixedOK faUncCanceled) ∧
    (oldStuck .canceled = [35, 36, 37] ∧ oldStuck faPure = [] ∧ oldStuck faError = [] ∧
     oldStuck faEmitCanceled = [35, 36, 37] ∧ oldStuck faStartEmitCanceled = [35, 36, 37] ∧
     oldStuck faCedeCanceled = [] ∧ oldStuck faUncCanceled = [35, 36, 37]) ∧
    grid.all (fun (i, j) => isDone (two faCedeCanceled 1 i j)) = true ∧
    grid.filter (fun (i, j) => stuck (two faCedeCanceled 0 i j)) =
      [(34, 12), (34, 13), (34, 14), (35, 11), (35, 12), (35, 13), (36, 11), (36, 12), (37, 11)] :=
  ⟨⟨fixed_onePreempt, old_onePreempt⟩,
   ⟨fam_fixed_canceled, fam_fixed_pure, fam_fixed_error, fam_fixed_emitCanceled,
    fam_fixed_startEmitCanceled, fam_fixed_cedeCanceled, fam_fixed_uncCanceled⟩,
   ⟨fam_old_canceled, fam_old_pure, fam_old_error, fam_old_emitCanceled, fam_old_startEmitCanceled,
    fam_old_cedeCanceled, fam_old_uncCanceled⟩,
   fam_fixed_cedeCanceled2, fam_old_cedeCanceled2⟩

end CatsEffectInLean.Proofs.Phase6.MemoizeStuckWitness
