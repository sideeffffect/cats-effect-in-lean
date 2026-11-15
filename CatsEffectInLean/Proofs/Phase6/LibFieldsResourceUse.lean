import CatsEffectInLean.Model.LibProbe
import CatsEffectInLean.Model.ResourceUse

/-!
# `ResourceUse.lib`: the function fields are complete (probe check, `Model/LibProbe.lean`)

`ResourceUse.lib` covers four closure families: `ULam` (this mirror), `Bracket.BLam` (with
`USrc` codes as external sources), Phase 5 `Clo` (with `ULam`-aware release functions), `Race` and
`Timeout` (both with `USrc` codes as sources).
The test runs each sample through the real dispatcher of the library (`UEnv.toEnv`, `resDisp`),
so every family is run as the statements run it. The `UEnv` of the test: user function `k`
returns `IO.delay(2 * k)` (program id); `bind`, `acquire`, `release` and `resOf` hold only the
handles of their argument (as `REnv.WellFormed` and the statement hypotheses require).
-/

namespace CatsEffectInLean.Proofs.Phase6.LibFieldsResourceUse

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceUse
open CatsEffectInLean.Model.LibProbe

/-- User function number of probe `i` (`probe i = 2 * q i`). -/
def q (i : Nat) : Nat := probe i / 2

/-- The `UEnv` of the test. -/
def probeU : UEnv where
  r := { user := { call := fun k _ _ => { out := .prog (.delay (.user (2 * k))) } }
         bind := fun _ a => .ok (.pure a)
         acquire := fun _ => .pure .unit
         release := fun _ a => .ok (.pure a) }
  resOf := fun c => some (.pure c)

/-- The `RelFn` codes, probes from `i`. -/
def rels (i : Nat) : List Val :=
  [RelFn.unit, .const (q i) (.nat (q (i + 1))), .user (q i), .guarantee (.user (q i)) (.user (q (i + 1)))].map
    RelFn.toVal

/-- The `onOutput` codes (`OnOut.user f` names program function `f`). -/
def onOuts (i : Nat) : List Val := [OnOut.user (probe i), .pure, .evalDesc, .unitFn].map OnOut.toVal

/-- The `onRelease` codes. -/
def onRels : List Val := [OnRel.apply, .store (.ref 5) 0, .store (.ref 5) 1].map OnRel.toVal

/-- The `USrc` codes, probes from `i` (the nested `attempt` code too). -/
def usrcs (i : Nat) : List Val :=
  (rels i).map (fun r => (USrc.relApp r (.nat (probe (i + 2))) (snapU {})).toVal) ++
  (rels i).map (fun r => (USrc.unitThen r (.nat (probe (i + 2)))).toVal) ++
  ((onOuts i).flatMap fun o => onRels.map fun rl => (USrc.fold (.nat (probe (i + 2))) o rl).toVal) ++
  (rels i).map (fun r => (USrc.attempt (USrc.relApp r (.nat (probe (i + 2))) (snapU {})).toVal).toVal)

/-- `Bracket` closures with `USrc` codes as external sources (`Src.ext`). -/
def blams : List Val :=
  (usrcs 0).flatMap fun s =>
    let e : Val := .left s
    let f : Val := .left (USrc.unitThen RelFn.unit.toVal .unit).toVal
    [Bracket.BLam.gBody e f, .gBody f e, .gOnError e, .gTap e, .constFin e, .constThis e,
     .gcBody e (probe 4), .dgcBody e (probe 4)].map Bracket.BLam.toVal

/-- The `ULam` closures, over the shapes of their fields. -/
def ulams : List Val :=
  (([AllocFn.user (q 0), .make (q 0) (q 1)].map ULam.allocFn) ++
   ([[], [q 0, q 1]].flatMap fun s => (onOuts 2).flatMap fun o => onRels.flatMap fun rl =>
     [ULam.foldUse s o rl, .foldEvalK s o rl]) ++
   onRels.map ULam.foldRel ++
   [ULam.allocatedBody (.nat (probe 0)), .allocatedK, .bothAlloc, .refNewThunk (.nat (probe 0)), .mcPair,
    .bothRel (.ref 5), .getThunk (.ref 5), .bothRelK (.nat (probe 0)), .voidK,
    .evalMapK (.nat (probe 0)) (.nat (probe 1)), .fixBothAlloc, .fixMcPair, .fixBothRel (.ref 5),
    .fixBothRelK (.nat (probe 0)), .fixRethrow] ++
   (rels 0).map (fun r => ULam.unitThenK r (.nat (probe 2))) ++
   ([0, 1].flatMap fun side => (rels 0).map fun r => ULam.updateThunk (.ref 5) side r) ++
   ((rels 0).flatMap fun f => (rels 2).flatMap fun r =>
     [ULam.storedFin f r, .storedFinK f r (.nat (probe 4))])).map ULam.toVal

/-- Phase 5 `Clo` closures, with every `RelFn` and `AllocFn` shape. -/
def clos : List Val :=
  (((rels 0).filterMap RelFn.ofVal).flatMap fun r => [[], [q 2, q 3]].flatMap fun s =>
    [Clo.evalK s r, .allocK s r (.poll 1 2), .onErrorH r, .allocBody (.user (q 4)) s r,
     .allocBody (.make (q 4) (q 5)) s r]).map Clo.toVal

/-- `Race` closures, with `USrc` codes as sources (`srcU` is their source builder here). -/
def rlams : List Val :=
  ([Race.Kind.race, .raceOutcome, .bothOutcome, .both].flatMap fun k => (usrcs 0).map fun a =>
    Race.RLam.body k a (USrc.unitThen RelFn.unit.toVal .unit).toVal).map Race.RLam.toVal ++
  (((usrcs 0).take 4 ++ (usrcs 0).drop 20).flatMap fun a =>
    [Race.RLam.thenMapPure a 0, .constV a, .tuple 1 a, .bothSel 0 a 1 2, .prodK a, .pairWith a,
     .thenJoin 3 a]).map Race.RLam.toVal ++
  [Race.RLam.sel .race 1 2, .thenRaise { code := 5 }, .joinSel 0 1 2, .inj 1, .constNever,
   .constPollCanceled 1 2].map Race.RLam.toVal

/-- `Timeout` closures (`IO.never` of `Race.constNever`), with `USrc` codes as sources. -/
def tlams : List Val :=
  (((usrcs 0).take 4 ++ (usrcs 0).drop 20).flatMap fun a =>
    [Timeout.TLam.body a (.some (USrc.unitThen RelFn.unit.toVal .unit).toVal) 3, .sel a 3 1 2, .embed a 1 2,
     .thenJoin a 3 4 .unit, .fold a 3]).map
    Timeout.TLam.toVal ++
  [Timeout.TLam.constNever, .fallbackThunk 3, .fallbackFlatten, .neverBody, .neverUnc 6,
   .neverSel 6 1 2].map Timeout.TLam.toVal

/-- All samples. -/
def samples : List Val := blams ++ ulams ++ clos ++ rlams ++ tlams

/-- Argument shapes that these closures need, probe-free: `(b, rel)`, `(a, release(a))`,
`(thisFin, thatFin)`, `((a, rel), outcome)`, `(x, y)` of `fixRethrow`. -/
def moreArgs : List Val :=
  [RelFn.unit, .const 3 .unit, .user 3].map (fun r => Val.pair .unit r.toVal) ++
  [.pair .unit (ioRelease 3 .unit), .pair RelFn.unit.toVal RelFn.unit.toVal,
   .pair (.pair .unit RelFn.unit.toVal) .ocCanceled,
   .pair (.pair .unit RelFn.unit.toVal) (.ocSucceeded .unit),
   .pair (.left (.err { code := 7 })) (.right .unit), .pair (.right .unit) (.right .unit)]

/-- The test on a group of samples. -/
def checkOn (lib : Lib) (cs : List Val) : Bool :=
  cs.all (sampleOK lib (args ++ moreArgs) id fun c a => probeU.toEnv.callV (2 * valToNat c + 1) a {})

/-- The test with a given library. -/
def check (lib : Lib) : Bool := checkOn lib samples

theorem blams_ok_0 : checkOn ResourceUse.lib (blams.take 64) = true := by decide +kernel
theorem blams_ok_1 : checkOn ResourceUse.lib ((blams.drop 64).take 64) = true := by decide +kernel
theorem blams_ok_2 : checkOn ResourceUse.lib (blams.drop 128) = true := by decide +kernel
theorem ulams_ok_0 : checkOn ResourceUse.lib (ulams.take 56) = true := by decide +kernel
theorem ulams_ok_1 : checkOn ResourceUse.lib (ulams.drop 56) = true := by decide +kernel
theorem clos_ok : checkOn ResourceUse.lib clos = true := by decide +kernel
theorem rlams_ok_0 : checkOn ResourceUse.lib (rlams.take 64) = true := by decide +kernel
theorem rlams_ok_1 : checkOn ResourceUse.lib ((rlams.drop 64).take 64) = true := by decide +kernel
theorem rlams_ok_2 : checkOn ResourceUse.lib (rlams.drop 128) = true := by decide +kernel
theorem tlams_ok : checkOn ResourceUse.lib tlams = true := by decide +kernel

private theorem split3 (l : List Val) (n : Nat) (p : Val → Bool) :
    l.all p = ((l.take n).all p && ((l.drop n).take n).all p && ((l.drop n).drop n).all p) := by
  conv => lhs; rw [← List.take_append_drop n l, ← List.take_append_drop n (l.drop n)]
  simp only [List.all_append, Bool.and_assoc]

private theorem split2 (l : List Val) (n : Nat) (p : Val → Bool) :
    l.all p = ((l.take n).all p && (l.drop n).all p) := by
  conv => lhs; rw [← List.take_append_drop n l]
  simp only [List.all_append]

/-- The function fields of `ResourceUse.lib` are complete for every sample. -/
theorem fields_complete : check ResourceUse.lib = true := by
  have hb := blams_ok_0; have hb1 := blams_ok_1; have hb2 := blams_ok_2
  have hu := ulams_ok_0; have hu1 := ulams_ok_1; have hc := clos_ok
  have hr := rlams_ok_0; have hr1 := rlams_ok_1; have hr2 := rlams_ok_2; have ht := tlams_ok
  simp only [checkOn] at *
  simp only [check, checkOn, samples, List.all_append, split3 blams 64, split2 ulams 56,
    split3 rlams 64, List.drop_drop, hb, hb1, hb2, hu, hu1, hc, hr, hr1, hr2, ht, Bool.and_self]

/-- The constructor indices of the samples of a code type. -/
def idxs {α : Type} (dec : Val → Option α) (idx : α → Nat) (cs : List Val) : List Nat :=
  cs.filterMap fun c => (dec c).map idx

/-- `ULam` decoded from a closure value. -/
def ulamOf (c : Val) : Option ULam :=
  (ofCloVal c).bind fun (_, tag, fs) => ULam.ofFields tag fs

/-- `RLam` decoded from a closure value. -/
def rlamOf (c : Val) : Option Race.RLam :=
  (ofCloVal c).bind fun (_, tag, fs) => Race.RLam.ofFields tag fs

/-- Every `ULam` constructor has a sample. -/
theorem covers_ulam : ∀ l : ULam, l.ctorIdx ∈ idxs ulamOf ULam.ctorIdx ulams := by
  have h : ∀ i, i < 23 → i ∈ idxs ulamOf ULam.ctorIdx ulams := by decide +kernel
  intro l; apply h; cases l <;> simp only [ULam.ctorIdx] <;> decide

/-- Every `RLam` constructor has a sample. -/
theorem covers_rlam : ∀ l : Race.RLam, l.ctorIdx ∈ idxs rlamOf Race.RLam.ctorIdx rlams := by
  have h : ∀ i, i < 14 → i ∈ idxs rlamOf Race.RLam.ctorIdx rlams := by decide +kernel
  intro l; apply h; cases l <;> simp only [Race.RLam.ctorIdx] <;> decide

/-- `TLam` decoded from a closure value. -/
def tlamOf (c : Val) : Option Timeout.TLam :=
  (ofCloVal c).bind fun (_, tag, fs) => Timeout.TLam.ofFields tag fs

/-- Every `TLam` constructor has a sample. -/
theorem covers_tlam : ∀ l : Timeout.TLam, l.ctorIdx ∈ idxs tlamOf Timeout.TLam.ctorIdx tlams := by
  have h : ∀ i, i < 11 → i ∈ idxs tlamOf Timeout.TLam.ctorIdx tlams := by decide +kernel
  intro l; apply h; cases l <;> simp only [Timeout.TLam.ctorIdx] <;> decide

/-- Every `USrc` constructor has a sample (as an external `Bracket` source and a `Race` source). -/
theorem covers_usrc : ∀ u : USrc, u.ctorIdx ∈ idxs USrc.ofVal USrc.ctorIdx (usrcs 0) := by
  have h : ∀ i, i < 4 → i ∈ idxs USrc.ofVal USrc.ctorIdx (usrcs 0) := by decide +kernel
  intro u; apply h; cases u <;> simp only [USrc.ctorIdx] <;> decide

/-- Every `OnOut`, `OnRel`, `RelFn` constructor has a sample. -/
theorem covers_onOut : ∀ o : OnOut, o.ctorIdx ∈ idxs OnOut.ofVal OnOut.ctorIdx (onOuts 2) := by
  have h : ∀ i, i < 4 → i ∈ idxs OnOut.ofVal OnOut.ctorIdx (onOuts 2) := by decide +kernel
  intro o; apply h; cases o <;> simp only [OnOut.ctorIdx] <;> decide

theorem covers_onRel : ∀ o : OnRel, o.ctorIdx ∈ idxs OnRel.ofVal OnRel.ctorIdx onRels := by
  have h : ∀ i, i < 2 → i ∈ idxs OnRel.ofVal OnRel.ctorIdx onRels := by decide +kernel
  intro o; apply h; cases o <;> simp only [OnRel.ctorIdx] <;> decide

theorem covers_rel : ∀ r : RelFn, r.ctorIdx ∈ idxs RelFn.ofVal RelFn.ctorIdx (rels 0) := by
  have h : ∀ i, i < 4 → i ∈ idxs RelFn.ofVal RelFn.ctorIdx (rels 0) := by decide +kernel
  intro r; apply h; cases r <;> simp only [RelFn.ctorIdx] <;> decide

/-- Wrong-function test: the fields before the probe check (no `srcCodeIds`) fail: a `Bracket`
or `Race` closure of this library hides the release function of a `USrc` source code. -/
theorem old_fields_fail :
    check { ok := ResourceUse.isLib, fields := fun c =>
      (match ofCloVal c with
       | some (k, tag, fs) => if k == ns then ((ULam.ofFields tag fs).map ULam.fnIds).getD [] else []
       | none => []) ++
      Bracket.fnFields c ++ ((Clo.ofVal c).map cloIds).getD [] } = false := by decide +kernel

/-- Wrong-function test: no fields fails. -/
theorem idFree_fails : check (Lib.idFree ResourceUse.isLib) = false := by decide +kernel

end CatsEffectInLean.Proofs.Phase6.LibFieldsResourceUse
