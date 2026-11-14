import CatsEffectInLean.Model.LibProbe
import CatsEffectInLean.Model.Bracket

/-!
# `Bracket.lib`: the function fields are complete (probe check, `Model/LibProbe.lean`)

`fields_complete`: every sample passes `LibProbe.sampleOK` with the real `Bracket.lib` and the
real `Bracket.call`. `covers`: every `BLam` constructor and every `Src` constructor (in every
`Src` position) has a sample. `wrong_fields`: a list without the `Src` fields fails the check.
-/

namespace CatsEffectInLean.Proofs.Phase6.LibFieldsBracket

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Bracket
open CatsEffectInLean.Model.LibProbe

/-- The four `Src` shapes, with probes from `i` (two per shape). -/
def srcs (i : Nat) : List Src :=
  [.ext (.nat (probe i)), .deferUse (probe i) (.nat (probe (i + 1))) 1 2,
   .pollUnitThen (probe i) (.nat (probe (i + 1))) 1 2, .pollDefer (probe i) (.nat (probe (i + 1))) 1 2]

private def p (i : Nat) : Nat := probe i
private def e : Err := { code := 5 }

/-- One sample per constructor; every pair of `Src` shapes for the two-`Src` constructor. -/
def samples : List BLam :=
  ((srcs 0).flatMap fun s => (srcs 2).map fun f => BLam.gBody s.toVal f.toVal) ++
  ((srcs 0).flatMap fun f => [BLam.gOnError f.toVal, BLam.gTap f.toVal, BLam.constFin f.toVal,
    BLam.constThis f.toVal, BLam.gcBody f.toVal (p 4), BLam.dgcBody f.toVal (p 4)]) ++
  [.raiseK e, .asK (.nat (p 0)), .reportK, .reportEc e, .reportThunk e,
   .gcOnError (p 0), .gcTap (p 0), .bfBody (p 0) (p 1) (p 2), .bfK (p 0) (p 1) 1 2,
   .deferThunk, .deferEv (p 0) (.nat (p 1)) 1 2, .relA (p 0) (.nat (p 1)), .dropOc (p 0),
   .dgcOnError (p 0), .unitH, .dgcTap (p 0), .dbfBody (p 0) (p 1) (p 2), .dbfK (p 0) (p 1) 1 2,
   .thenUse (p 0) (.nat (p 1)), .fbfBody (p 0) (p 1) (p 2), .fbfK (p 0) (p 1) 1 2]

/-- The test with a given library. -/
def check (lib : Lib) : Bool :=
  samples.all (sampleOK lib args BLam.toVal fun l a => call recUC (fun s => .pure s) l a {})

/-- The function fields of `Bracket.lib` are complete for every sample. -/
theorem fields_complete : check Bracket.lib = true := by decide +kernel

/-- Every `BLam` constructor has a sample. -/
theorem covers_blam : ∀ l : BLam, l.ctorIdx ∈ samples.map BLam.ctorIdx := by
  have h : ∀ i, i < 28 → i ∈ samples.map BLam.ctorIdx := by decide +kernel
  intro l; apply h; cases l <;> simp only [BLam.ctorIdx] <;> decide

/-- Every `Src` constructor has a sample in each position (`srcs`). -/
theorem covers_src : ∀ s : Src, ∀ i, s.ctorIdx ∈ (srcs i).map Src.ctorIdx := by
  intro s i; cases s <;> simp [srcs, Src.ctorIdx]

/-- Wrong-function test: `fields` without the `Src` codes (the defect class of `ptLibDeep`)
fails the check. -/
theorem wrong_fields :
    check { ok := isLib, fields := fun c =>
      match Codec.ofCloVal c with
      | some (k, tag, fs) =>
        if k == ns then
          ((BLam.ofFields tag fs).map fun
            | .gcBody _ k | .dgcBody _ k => [k]
            | l => if (l.fnIds).isEmpty then [] else BLam.fnIds l).getD []
        else []
      | none => [] } = false := by decide +kernel

/-- Wrong-function test: no fields at all (`Lib.idFree`) fails the check. -/
theorem idFree_fails : check (Lib.idFree isLib) = false := by decide +kernel

end CatsEffectInLean.Proofs.Phase6.LibFieldsBracket
