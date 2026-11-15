import CatsEffectInLean.Props.Phase6.ParTraverse

/-!
# `parTraverseN`: forgeries of review batches 7 and 8 under decision 58

Decision 58 makes every function field of `Model/ParTraverse.lean` a closure reference
(`Val.fn`). `WellFormed` then follows it structurally (`WF.avail`): user code may name a reference
only if it holds it, or if it is one of its own user closures whose captured handles are available.
These kernel-checked examples use the real codes and the `Lib`s of the statements.

* Batch 7, defect D: `f` captured the result `Deferred` of an input and was named in `PT.k1`.
* The same `f` in a `Bracket.guaranteeCase` source and in a `Race.both` source.
* Batch 8, F2: the same `f` under `.some` in a `Timeout.fold` fallback source.
* Batch 8, F3: an `f` that captured the semaphore state `Ref`, in the same position (statement 8).
* Honest user functions (no captured handle) in the same positions are accepted.
-/

namespace CatsEffectInLean.Proofs.Phase6.ParTraversePrivacy

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.ParTraverse
open CatsEffectInLean.Props.Phase6.ParTraverse

/-- A user closure that captured `Deferred 5` (a result cell of an input). -/
def fForge : Nat := 2 * valToNat (.deferred 5)

/-- A user closure that captured `Ref 3` (the semaphore state of statement 8). -/
def fSem : Nat := 2 * valToNat (.ref 3)

/-- An honest user function (closure value `0`, no handle). -/
def fOk : Nat := 14

/-! ## Defect D: the root of statement 1 -/

example : WF.progOK ptLibDeep (fun _ => false) (orderRoot 1 [.nat 0] fForge) = false := by decide +kernel
example : WF.progOK ptLibDeep (fun _ => false) (orderRoot 1 [.nat 0] fOk) = true := by decide +kernel
example : WF.progOK ptLibDeep (fun _ => false) (parTraverseNIO 1 [.nat 0] fForge) = false := by decide +kernel
example : WF.progOK ptLibDeep (fun _ => false) (parTraverseNIO 1 [.nat 0] fOk) = true := by decide +kernel

/-- The harness closure `TL.tag f` is not public: user code cannot name it (only the root does,
through `TL.start`). -/
example : WF.progOK ptLibDeep (fun _ => false) (.flatMap (.pure .unit) (.user (TL.tag fOk).id)) = false := by
  decide +kernel

/-! ## The forging `f` in library sources -/

example : WF.progOK ptLibDeep (fun _ => false)
    (Bracket.guaranteeCaseIO (.ext (srcAction fForge (.nat 0))) fOk) = false := by decide +kernel
example : WF.progOK ptLibDeep (fun _ => false)
    (Bracket.guaranteeCaseIO (.ext (srcAction fOk (.nat 0))) fOk) = true := by decide +kernel
example : WF.progOK ptLibDeep (fun _ => false)
    (Race.bothIO (srcAction fForge (.nat 0)) (srcAction fOk (.nat 0))) = false := by decide +kernel
example : WF.progOK ptLibDeep (fun _ => false)
    (Race.bothIO (srcAction fOk (.nat 0)) (srcAction fOk (.nat 0))) = true := by decide +kernel

/-! ## Batch 8, F2 and F3: under `.some` in a `Timeout.fold` fallback -/

/-- The program that the traversed `f` returns in F2/F3. -/
def foldProg (g : Nat) : IO :=
  .flatMap (.pure .ocCanceled) (Timeout.TLam.fold (.some (srcAction g (.nat 0))) 3).fn

example : WF.progOK ptLibDeep (fun _ => false) (foldProg fForge) = false := by decide +kernel
example : WF.progOK limLib (fun _ => false) (foldProg fSem) = false := by decide +kernel
example : WF.progOK ptLibDeep (fun _ => false) (foldProg fOk) = true := by decide +kernel
example : WF.progOK limLib (fun _ => false) (foldProg fOk) = true := by decide +kernel

/-! ## Statement 8: the harness closures that hold the counter cell are not available -/

example : WF.progOK limLib (fun _ => false) (.delay (CL.enter 0).fn) = false := by decide +kernel
example : WF.progOK limLib (fun _ => false) (.flatMap (.pure .unit) (CL.body 0 fOk).fn) = false := by
  decide +kernel
example : WF.progOK limLib (fun _ => false) (limitRoot 1 [.nat 1, .nat 2] fOk) = true := by decide +kernel
example : WF.progOK limLib (fun _ => false) (limitRoot 1 [.nat 1, .nat 2] fSem) = false := by decide +kernel

end CatsEffectInLean.Proofs.Phase6.ParTraversePrivacy
