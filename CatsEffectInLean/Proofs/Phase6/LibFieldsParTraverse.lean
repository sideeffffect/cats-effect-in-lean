import CatsEffectInLean.Model.LibProbe
import CatsEffectInLean.Props.Phase6.ParTraverse

/-!
# `ptLibDeep`: the function fields are complete (probe check, `Model/LibProbe.lean`)

Track R's check of track G's library (`Props/Phase6/ParTraverse.lean`, `ptLibDeep`); this file
does not change it. The test runs each sample through the dispatcher of the statements
(`ParTraverse.env ho (tagged u)`), with `u` the probe environment `LibProbe.recUC`. Each `Val`
field gets every shape of `vals`: a probe number, a `srcAction` code, a `srcAction` code inside a
list and under `.left` (a nested code, the defect class of the first `ptLibDeep`).
-/

namespace CatsEffectInLean.Proofs.Phase6.LibFieldsParTraverse

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.ParTraverse
open CatsEffectInLean.Model.LibProbe
open CatsEffectInLean.Props.Phase6.ParTraverse

/-- The `Val` field shapes, probes from `i` (two per shape). -/
def vals (i : Nat) : List Val :=
  [.nat (probe i), srcAction (probe i) (.nat (probe (i + 1))),
   listV [srcAction (probe i) (.nat (probe (i + 1)))], .left (srcAction (probe i) (.nat (probe (i + 1))))]

private def p (i : Nat) : Nat := probe i

/-- One sample per constructor, over the `Val` shapes. Handles: `Deferred` 1, `Ref` 2, fiber 3,
poll `(1, 2)`. -/
def samples : List PT :=
  ((vals 10).flatMap fun a =>
    [PT.newRef a, .k1 2 a (p 0), .k2 2 a (p 0) 1, .k3 a (p 0) 1 2, .travM2 (p 0) 1 2 2 a, .snoc a,
     .elemSel (p 0) 1 2 2 a, .uncK (p 0) 1 2 2 a, .resK (p 0) 1 2 2 a 1 2, .thenStart (p 0) 1 2 2 a 1,
     .callF (p 0) a, .compSucc 1 a, .plCancelAll 2 a, .asK a, .seqM2 a, .caK a, .constJoin 3 a]) ++
  [.newDeferred, .semK, .toList, .tryGet 1, .finK 1 2 2 1, .ifErr 2 1 { code := 5 }, .ifCan 2 1,
   .plStartCancelAll 2, .thenRelease 2, .voidK, .unitH, .fibK 1 2 1, .supAdd 2 3 1, .supRemove 2 3 1,
   .thenAfter 1 2 3 1, .selAfter 2 3 1, .finRes 2 3 1, .embedK, .constNever, .seqK, .refGet 2,
   .ifCancel 3, .ifCA 2, .thenJoinAll 2, .joinAllK, .acqBody 2, .acqWait 2 1 2, .modAcq 2 1 1 2,
   .flattenK, .wonK 2, .relBody 2, .modRel 2]

/-- The source codes of this library (`ioOf`): `srcAction f a`, `srcResGet`, `srcPar`. -/
def srcs : List Val :=
  [srcAction (p 0) (.nat (p 1)), srcResGet 1 .none, srcPar (listV [.pair (.fiber 3) (.deferred 1)]) .unit]

/-- `Bracket`, `Race` and `Timeout` closures with these sources (`ioOf` is their source builder
here; the defect class of the first `ptLibDeep`). -/
def others : List Val :=
  (srcs.flatMap fun a =>
    let e : Val := .left a
    let f : Val := .left (srcResGet 2 .none)
    [Bracket.BLam.gBody e f, .gBody f e, .gOnError e, .gTap e, .constFin e, .constThis e,
     .gcBody e (p 4), .dgcBody e (p 4)].map Bracket.BLam.toVal ++
    [Race.Kind.race, .raceOutcome, .bothOutcome, .both].map (fun k =>
      (Race.RLam.body k a (srcResGet 2 .none)).toVal) ++
    [(Race.RLam.body .both (srcResGet 2 .none) a).toVal,
     (Timeout.TLam.body a .none 3).toVal, (Timeout.TLam.body (srcResGet 2 .none) (.some a) 3).toVal,
     (Timeout.TLam.sel a 3 1 2).toVal])

/-- The harness closures of the statements (`TL`). -/
def tls : List Val := [TL.tag (p 0), .pairWith (.nat (p 0)), .pairWith (srcAction (p 0) (.nat (p 1)))].map TL.toVal

/-- The environment of the statements with the probe user code (input order kept). -/
def probeEnv : UserEnv := ParTraverse.env id (tagged { call := fun k a _ => recUC k a {} })

/-- Argument shapes that these closures need, probe-free: lists, an outcome with a value. -/
def moreArgs : List Val :=
  [listV [.unit], listV [], .pair (listV []) (.nat 0), .ocSucceeded (listV [.unit])]

/-- The test with a given library, on a group of samples. -/
def checkOn (lib : Lib) (cs : List Val) : Bool :=
  cs.all (sampleOK lib (args ++ moreArgs) id fun c a => probeEnv.callV (2 * valToNat c + 1) a {})

/-- All samples as closure values. -/
def all : List Val := samples.map PT.toVal ++ tls ++ others

/-- The test with a given library. -/
def check (lib : Lib) : Bool := checkOn lib all

theorem ok_0 : checkOn ptLibDeep (all.take 40) = true := by decide +kernel
theorem ok_1 : checkOn ptLibDeep ((all.drop 40).take 40) = true := by decide +kernel
theorem ok_2 : checkOn ptLibDeep (all.drop 80) = true := by decide +kernel

/-- The function fields of `ptLibDeep` are complete for every sample. -/
theorem fields_complete : check ptLibDeep = true := by
  have h0 := ok_0; have h1 := ok_1; have h2 := ok_2
  simp only [checkOn] at *
  have e : all = all.take 40 ++ ((all.drop 40).take 40 ++ (all.drop 40).drop 40) := by
    simp only [List.take_append_drop]
  simp only [check, checkOn]
  rw [e, List.all_append, List.all_append, List.drop_drop] at *
  simp only [h0, h1, h2, Bool.and_self]

/-- Wrong-function test: the first `ptLibDeep` (no `srcAction` fields) fails the check. -/
theorem first_fields_fail :
    checkOn { ok := ptIsLib, fields := fun c =>
      (match ofCloVal c with
       | some (k, tag, fs) => if k == ns then ((PT.ofFields tag fs).map PT.fnIds).getD [] else []
       | none => []) ++ Bracket.fnFields c ++
      (match ofCloVal c with
       | some (42, 0, [.nat f]) => [f]
       | _ => []) } ((all.drop 103).take 1) = false := by decide +kernel

/-- Every `PT` constructor has a sample. -/
theorem covers : ∀ l : PT, l.ctorIdx ∈ samples.map PT.ctorIdx := by
  have h : ∀ i, i < 49 → i ∈ samples.map PT.ctorIdx := by decide +kernel
  intro l; apply h; cases l <;> simp only [PT.ctorIdx] <;> decide

end CatsEffectInLean.Proofs.Phase6.LibFieldsParTraverse
