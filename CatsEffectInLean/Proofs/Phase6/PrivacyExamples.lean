import CatsEffectInLean.Proofs.Phase6.ResourceWitness
import CatsEffectInLean.Proofs.Phase6.BracketWitness

/-!
# Regression: the forgeries of review batches 4-6 are rejected (decision 56)

Each forgery that a review found is a Lean `example` here: the hypothesis of the current
statements rejects it (`decide +kernel`). See `Props/Phase6/HarnessPrivacy.lean` for the
construction that closes the whole class; these examples only guard against regressions.

* Batch 4 (track G): the marker hypothesis `MarkersOnly` could never hold together with the
  others (vacuous). Regression: the satisfiability witnesses (decision 53) exist for every
  statement: `BracketWitness.bracketReleaseOnce_satisfiable`, `guaranteeFinalizerOnce_satisfiable`,
  `ResourceWitness.use_sat`, `flat_sat`, and the CE-0020 refutation.
* Batch 5 (track Res): a marker forwarded through a library closure field
  (`ULam.allocFn (.user mR)`), and the same through other fields.
* Batch 6 (track G): a `Bracket` leaf that captured a counter handle, named by number in
  `BLam.thenUse` (the shallow `captured` accepted it; the deep one does not).
* Batch 6 (track Res): a clock number used as a harness name (`IO.sleep n >> IO.realTime`, then a
  user function returns a program that names `n`); and a resource code `c = .unit`.
-/

namespace CatsEffectInLean.Proofs.Phase6.PrivacyExamples

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceUse
open CatsEffectInLean.Props.Phase6.Resource
open CatsEffectInLean.Props.Phase6.HarnessPrivacy
open CatsEffectInLean.Proofs.Phase6.ResourceWitnessEnv

/-! ## Batch 4: the hypotheses are satisfiable -/

example := @CatsEffectInLean.Proofs.Phase6.BracketWitness.bracketReleaseOnce_satisfiable
example := @CatsEffectInLean.Proofs.Phase6.BracketWitness.guaranteeFinalizerOnce_satisfiable
example := @CatsEffectInLean.Proofs.Phase6.ResourceWitness.use_sat
example := @CatsEffectInLean.Proofs.Phase6.ResourceWitness.flat_sat

/-! ## Batch 5 (track Res): forwarding through a library closure field -/

/-- The event closure of release (`markT RA`) forwarded by number in `ULam.allocFn`: the user
result names the token. -/
example : tokFreeIO toks (.map (.pure .unit) (ULam.allocFn (.user (HLam.markT logCell tagRA).id)).fn) = false := by
  decide +kernel

/-- The marked `make` itself, named by its codes (acquire and release would run again). -/
example : tokFreeIO toks (.map (.pure .unit) (ULam.allocFn (.make (code 0) (code 1))).fn) = false := by
  decide +kernel

/-- The release code in `Clo.makePair` (a `RelFn.const` for the harness release). -/
example : tokFreeIO toks (.flatMap (.pure .unit) (cloFn (.makePair (code 1)))) = false := by
  decide +kernel

/-- The release code in a `RelFn` value that a user `Allocate` function returns (data that the
library reads as a release function). -/
example : tokFreeR toks { out := .ret (.pair .unit (RelFn.const (code 1) .unit).toVal) } = false := by
  decide +kernel

/-- The harness resource code in a rebuilt `fold` source (`USrc.fold`). -/
example : tokFreeIO toks (Race.bothIO (USrc.fold cA OnOut.pure.toVal OnRel.apply.toVal).toVal (.nat 0)) = false := by
  decide +kernel

/-- The event closure named directly is not in the statement's `Lib`. -/
example : WF.progOK libH (fun _ => false) (.delay (HLam.markT logCell tagRA).fn) = false := by
  decide +kernel

/-! ## Batch 6 (track Res): runtime numbers and the resource code `.unit` -/

/-- The clock forgery: the user function gets the clock value `n` (the id of the release event
closure, after `IO.sleep n >> IO.realTime`) and returns a program that runs it. The result names
the token, so `Private` rejects it, whatever the argument was (no escape clause). -/
example : tokFreeR toks { out := .prog (.delay (.user (HLam.markT logCell tagRA).id)) } = false := by
  decide +kernel

/-- The same with the number as returned data (a harness code). -/
example : tokFreeR toks { out := .ret (.nat (code 1)) } = false := by decide +kernel

/-- A resource code `.unit` is not a token name, so it cannot be the code of a marked `make`
(`MarkedMake` needs `tokFreeV toks c = false`). -/
example : tokFreeV toks .unit = true := by decide +kernel

/-- `WellFormed` rejects a write of the log cell (not held). -/
example : tokFreeR toks { effects := [.writeRef logCell (Codec.listV [tagRA])], out := .ret .unit } = false := by
  decide +kernel

/-! ## Batch 6 (track G): a `Bracket` leaf that captured a counter handle, named by number -/

section TrackG
open CatsEffectInLean.Model.Bracket
open CatsEffectInLean.Props.Phase6.Bracket (srcAcq srcFa HLam)

/-- The leaf `_ => this` whose `this` is the acquire program with counter 0. -/
def leafAcq : Nat := (BLam.constThis (Src.ext (srcAcq 0)).toVal).id
def leafFa : Nat := (BLam.constThis (Src.ext (srcFa 0 6)).toVal).id

/-- The forged program: `IO.unit.flatMap(_ => leaf(()))` through `thenUse`. -/
def forged (leaf : Nat) : IO := .flatMap (.pure .unit) (BLam.thenUse leaf .unit).fn

/-- With the shallow capture (a `Lib` without function fields, the old `WellFormed`) the forgery
passes: this was the gap. -/
example : WF.progOK (Bracket.isLib : Lib) (fun _ => false) (forged leafAcq) = true := by decide +kernel

/-- With the deep capture (`Bracket.lib`, decision 56) it is rejected: it needs the counter
handle `Ref` 0. -/
example : WF.progOK Bracket.lib (fun _ => false) (forged leafAcq) = false := by decide +kernel
example : WF.progOK Bracket.lib (fun _ => false) (forged leafFa) = false := by decide +kernel

/-- The clock forgery for track G: a number that is the id of a counter event closure, named in a
program, is not in `Bracket.lib` (and captures the counter handle). -/
example : WF.progOK Bracket.lib (fun _ => false) (.delay (HLam.markThunk 0).fn) = false := by decide +kernel
example : WF.progOK Bracket.lib (fun _ => false) (.flatMap (.pure .unit) (BLam.thenUse (HLam.markThunk 0).id .unit).fn) = false := by
  decide +kernel

end TrackG

end CatsEffectInLean.Proofs.Phase6.PrivacyExamples
