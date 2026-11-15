import CatsEffectInLean.Proofs.Phase6.ResourceWitness
import CatsEffectInLean.Proofs.Phase6.BracketWitness
import CatsEffectInLean.Model.Timeout

/-!
# Regression: the forgeries of review batches 4-8 are rejected (decision 58)

Decision 58: a closure reference is a `Val.fn` value, separate from data numbers. `WellFormed`
follows references structurally (`Val.handles`) and holds user code to the available handles
(`WF.avail`): what it received, and its own user closures (even ids) whose captured handles are
available. A library closure (odd id) is available only if held, or (in a program) if `Lib.ok`
allows it and its captured handles are available. Each forgery that a review found is a Lean
`example` here (`decide +kernel`).

* Batch 4 (track G): vacuous hypotheses. Regression: the satisfiability witnesses (decision 53).
* Batch 5 (track Res): a marker forwarded through a library closure field (`ULam.allocFn`).
* Batch 6 (track G): a `Bracket` leaf that captured a counter handle, named in `BLam.thenUse`.
* Batch 6 (track Res): a clock number used as a closure name.
* Batch 8, F1: a `Bracket` external source whose data names a harness closure (`hioOf`).
* Batch 8, F2: a reference nested under `.some` in a `Timeout.fold` fallback source
  (`parTraverseN`). F3: the same reference writes the semaphore `Ref` of statement 8. Shown here in
  the form that decision 58 gives the `parTraverseN` codes (`srcAction` with a `Val.fn` field;
  track G switches `Model/ParTraverse.lean` to it).
* Batch 8, S1: user code may pass any value through (`x => IO.pure(x)` passes `CallOK`).
-/

namespace CatsEffectInLean.Proofs.Phase6.PrivacyExamples

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Model.ResourceUse
open CatsEffectInLean.Props.Phase6.Resource
open CatsEffectInLean.Proofs.Phase6.ResourceWitnessEnv

/-! ## Batch 4: the hypotheses are satisfiable -/

example := @CatsEffectInLean.Proofs.Phase6.BracketWitness.bracketReleaseOnce_satisfiable
example := @CatsEffectInLean.Proofs.Phase6.BracketWitness.guaranteeFinalizerOnce_satisfiable
example := @CatsEffectInLean.Proofs.Phase6.ResourceWitness.use_sat
example := @CatsEffectInLean.Proofs.Phase6.ResourceWitness.flat_sat

/-! ## Batch 5 (track Res): forwarding through a library closure field -/

/-- `ULam.allocFn (.user mT)` in a user program: `ULam` is internal (not in `libH.ok`), and the
reference to the event closure `markT` is not available. -/
example : WF.progOK libH (fun _ => false)
    (.map (.pure .unit) (ULam.allocFn (.user (HLam.markT logCell tagRA).id)).fn) = false := by
  decide +kernel

/-- The event closure itself, named in a program. -/
example : WF.progOK libH (fun _ => false) (.delay (HLam.markT logCell tagRA).fn) = false := by
  decide +kernel

/-- A `Race` closure (public) whose source names the event closure by reference: rejected. -/
example : WF.progOK libH (fun _ => false)
    (Race.bothIO (USrc.relApp (RelFn.user (HLam.markT logCell tagRA).id).toVal .unit (snapU {})).toVal
      (.nat 0)) = false := by
  decide +kernel

/-! ## Batch 6 (track Res): runtime numbers name nothing -/

/-- A program that names the event closure by a number computed at run time is still rejected:
the id is odd, not in `libH.ok`, and not held. -/
example : WF.fnOK libH (fun _ => false) (.user (HLam.markT logCell tagRA).id) = false := by
  decide +kernel

/-- A data number is only data: returning it needs nothing. -/
example : WF.subA (fun _ => false) (Val.nat (HLam.markT logCell tagRA).id).handles = true := by
  decide +kernel

/-! ## Batch 6 (track G): a `Bracket` leaf that captured a counter handle -/

section TrackG
open CatsEffectInLean.Model.Bracket
open CatsEffectInLean.Props.Phase6.Bracket

def leafAcq : Nat := (BLam.constThis (Src.ext (srcAcq 0)).toVal).id

/-- `thenUse` names the leaf by reference (`Val.fn`); the leaf captured the counter `Ref` 0, which
is not held. -/
example : WF.progOK Bracket.lib (fun _ => false) (.flatMap (.pure .unit) (BLam.thenUse leafAcq .unit).fn) = false := by
  decide +kernel

/-! ## Batch 8, F1: a `Bracket` external source that names a harness closure -/

/-- The forged source of F1: the user's own cell `r = 2`, and the harness release counter's
event closure `markA 1` as a reference (`hioOf` runs it). -/
def f1Src : Val := .pair (.ref 2) (.pair (.nat 1) (.fn (Props.Phase6.Bracket.HLam.markA 1).id))

/-- The F1 program: `IO.unit.flatMap(constThis(Src.ext f1Src))`, built by user code that holds
only its cell `Ref` 2. Rejected: `markA 1` is a library closure that the user does not hold. -/
example : WF.progOK Bracket.lib (fun h => h == .ref 2)
    (.flatMap (.pure .unit) (BLam.constThis (Src.ext f1Src).toVal).fn) = false := by
  decide +kernel

/-- The honest form: the same source with the user's own closure `k = 14` (no captured handle). -/
example : WF.progOK Bracket.lib (fun h => h == .ref 2)
    (.flatMap (.pure .unit) (BLam.constThis (Src.ext (.pair (.ref 2) (.pair (.nat 1) (.fn 14)))).toVal).fn) = true := by
  decide +kernel

end TrackG

/-! ## Batch 8, F2 and F3: a reference under `.some` in a `Timeout.fold` fallback -/

section F2
open CatsEffectInLean.Model.Timeout

/-- The `srcAction f a` code of `Model/ParTraverse.lean` in the form of decision 58. -/
def srcActionFn (f : Nat) (a : Val) : Val := cloVal 41 80 [.fn f, a]

/-- F2: the forging function of review batch 7, a user closure that captured the element's result
`Deferred` 5. -/
def fForge : Nat := 2 * valToNat (.deferred 5)

/-- The traversed function returns `IO.pure(Canceled).flatMap(fold(Some(srcAction fForge 0), 3))`.
Rejected: the reference to `fForge` is found under `.some`, and `fForge` captured `Deferred` 5. -/
example : WF.progOK (fun id => (Codec.isLibId id)) (fun _ => false)
    (.flatMap (.pure .ocCanceled) (TLam.fold (.some (srcActionFn fForge (.nat 0))) 3).fn) = false := by
  decide +kernel

/-- F3: the same with a forging function that captured the semaphore state `Ref` 7. -/
example : WF.progOK (fun id => (Codec.isLibId id)) (fun _ => false)
    (.flatMap (.pure .ocCanceled) (TLam.fold (.some (srcActionFn (2 * valToNat (.ref 7)) (.nat 0))) 3).fn) = false := by
  decide +kernel

/-- An honest function (captures nothing) in the same position is accepted. -/
example : WF.progOK (fun id => (Codec.isLibId id)) (fun _ => false)
    (.flatMap (.pure .ocCanceled) (TLam.fold (.some (srcActionFn 14 (.nat 0))) 3).fn) = true := by
  decide +kernel

end F2

/-! ## Batch 8, S1: user code may pass any value through -/

/-- `x => IO.pure(x)` (user function 0, closure id 0). -/
def idEnv : UserEnv where
  call _ arg _ := { out := .prog (.pure arg) }

/-- It passes `CallOK` on every argument, also one that holds a token or a harness reference: it
returns only what it received. -/
theorem idEnv_callOK (arg : Val) (v : View) : WF.CallOK libH [] idEnv 0 arg v := by
  refine WF.callOK_of_reach (fun _ _ => rfl) ?_
  show WF.progOK libH _ (.pure arg) = true
  simp only [WF.progOK, WF.subA, List.all_eq_true]
  intro h hh
  exact WF.avail_of_mem ((WF.memOf_eq _ _).2 (WF.Reach.base (by simp [hh])))

end CatsEffectInLean.Proofs.Phase6.PrivacyExamples
