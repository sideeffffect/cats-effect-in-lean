import CatsEffectInLean.Props.Phase7.Queue

/-!
# Wrong-function tests of the `Queue` statements (kernel-checked)

Each wrong function replaces one closure of a queue mirror by a broken version (as the review
rubric asks: "drop an element", "never wake a taker", "duplicate", "LIFO", "cancel hangs"). For
each, one concrete harness run (fuel 3000, FIFO schedule `[]`, kernel-checked) breaks the claim
of the statement, while the real mirror (`henv`) meets the claim on the same input. So the claims
see the defects they are about. `tools/QSmoke/Main.lean` runs the same wrong functions under random
schedules.

| Wrong function | Statement broken | Input |
|---|---|---|
| `wDrop`: `AbstractQueue#offer` wakes a waiting taker but does not enqueue | `concNoLoss` | `boundedForConcurrent(2)`, `[[take], [offer 1]]`, plan `[(2, 0)]` |
| `wDropAsync`: `UnboundedAsyncQueue#offer` notifies but does not put | `asyncNoLoss` | `unbounded`, same |
| `wDup`: `AbstractQueue#take` returns the head but keeps it | `concNoDup` | `boundedForConcurrent(2)`, `[[offer 1, take]]` |
| `wDupAsync`: `BaseBoundedAsyncQueue#take` returns the head but keeps it | `asyncNoDup` | `bounded(2)`, `[[offer 1, take]]` |
| `wLifoConc`: `AbstractQueue#tryTake` takes the last element | `concFifo` | `boundedForConcurrent(3)`, `[[offer 1, offer 2, tryTake]]` |
| `wLifo`: `BaseBoundedAsyncQueue#tryTake` takes the last element | `asyncFifo` | `bounded(3)`, same |
| `wHangConc`: the `cleanup` of a canceled `AbstractQueue#take` waits for its own taker | `concNoDeadlock` | `boundedForConcurrent(1)`, `[[take]]`, plan `[(1, 0)]` |
| `wHangAsync`: `UnboundedAsyncQueue#take` waits in `get` without `poll` (cannot be canceled) | `asyncNoDeadlock` | `unbounded`, same |
| `wNoWake`: `AbstractQueue#offer` enqueues but does not complete the taker | `concTakerLiveness` | `boundedForConcurrent(2)`, `[[take], [offer 1]]`, join `[0]` |
| `wNoNotify`: `UnboundedAsyncQueue#offer` puts but does not notify | `asyncTakerLiveness` | `unbounded`, same |
-/

namespace CatsEffectInLean.Proofs.Phase7.QueueWrongFunction

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Std
open CatsEffectInLean.Std.QueueFactory
open CatsEffectInLean.Props.Phase7.Queue

/-- `henv` with the closure results of the queue mirrors replaced by `f` where it answers. -/
def wrap (f : Nat → Val → View → Option UserResult) : UserEnv where
  call id arg refs := (f id arg { refs }).getD (henv.callV id arg { refs })
  callV id arg v := (f id arg v).getD (henv.callV id arg v)

open QueueConcurrent in
def wDrop : UserEnv := wrap fun id _ v =>
  match QC.ofId? id with
  | some (.offerMod o _ _ _ _) =>
    match absState v o with
    | some (_, _, s, st) =>
      match st.takers with
      | t :: rest => some { effects := [.writeRef s { st with takers := rest }.toVal], out := .ret (dCompleteVoid t .unit) }
      | [] => none
    | none => none
  | _ => none

open QueueAsync in
def wDropAsync : UserEnv := wrap fun id _ v =>
  match QA.ofId? id with
  | some (.uOffer o _) =>
    match Obj.ofId? o with
    | some (.unb b) => some { effects := notifyAt (b + 1) (waitersOf v (b + 1)), out := .ret .unit }
    | _ => none
  | _ => none

open QueueConcurrent in
def wDup : UserEnv := wrap fun id _ v =>
  match QC.ofId? id with
  | some (.takeMod o _ _ _) =>
    match absState v o with
    | some (_, _, _, st) =>
      match st.queue, st.offerers with
      | a :: _, [] => some { out := .ret (dPure a) }
      | _, _ => none
    | none => none
  | _ => none

open QueueAsync in
def wDupAsync : UserEnv := wrap fun id _ v =>
  match QA.ofId? id with
  | some (.bTakeThunk o _ _) =>
    match Obj.ofId? o with
    | some (.bnd _ _ b) =>
      match bufOf v b with
      | a :: _ => some { out := .ret (dPure a) }
      | [] => none
    | _ => none
  | _ => none

open QueueConcurrent in
def wLifoConc : UserEnv := wrap fun id _ v =>
  match QC.ofId? id with
  | some (.tryTakeMod o) =>
    match absState v o with
    | some (_, _, s, st) =>
      match st.queue.reverse, st.offerers with
      | a :: rest, [] =>
        some { effects := [.writeRef s { st with queue := rest.reverse, size := st.size - 1 }.toVal], out := .ret (dPure (.some a)) }
      | _, _ => none
    | none => none
  | _ => none

open QueueAsync in
def wLifo : UserEnv := wrap fun id _ v =>
  match QA.ofId? id with
  | some (.bTryTake o) =>
    match Obj.ofId? o with
    | some (.bnd _ _ b) =>
      match (bufOf v b).reverse with
      | a :: rest => some { effects := [.writeRef b (listV rest.reverse)], out := .ret (.some a) }
      | [] => none
    | _ => none
  | _ => none

open QueueConcurrent in
/-- The `cleanup` of a canceled `take` waits for its own taker `Deferred`, which nobody completes. -/
def wHangConc : UserEnv := wrap fun id _ _ =>
  match QC.ofId? id with
  | some (.cleanupTake _ t) => some { out := .ret (dPollGet t 0 0) }
  | _ => none

open QueueAsync in
/-- `asyncCheckAttempt` without `poll`: `Left(Some(fin))` gives `get` (masked), so a waiting `take`
cannot be canceled and `cancel` waits forever. -/
def wHangAsync : UserEnv := wrap fun id arg _ =>
  match QA.ofId? id, arg with
  | some (.uWaitSel _ s _ _), .left (.some _) => some { out := .prog (.contGet s) }
  | _, _ => none

open QueueConcurrent in
def wNoWake : UserEnv := wrap fun id _ v =>
  match QC.ofId? id with
  | some (.offerMod o a _ _ _) =>
    match absState v o with
    | some (_, _, s, st) =>
      match st.takers with
      | _ :: _ => some { effects := [.writeRef s { st with queue := st.queue ++ [a], size := st.size + 1 }.toVal], out := .ret dUnit }
      | [] => none
    | none => none
  | _ => none

open QueueAsync in
def wNoNotify : UserEnv := wrap fun id _ v =>
  match QA.ofId? id with
  | some (.uOffer o a) =>
    match Obj.ofId? o with
    | some (.unb b) => some { effects := [.writeRef b (listV (bufOf v b ++ [a]))], out := .ret .unit }
    | _ => none
  | _ => none

/-- A run of a harness root with environment `e` (FIFO schedule, fuel 3000). -/
def runWith (e : UserEnv) (k : QKind) (s : List (List Op)) (p : List (Nat × Nat)) (m : Mode) : Option Obs :=
  runObsP {} counterMaskModel e 3000 [] (rootIO k s p m)

def subMultiB (a b : List Val) : Bool := a.all fun x => a.count x ≤ b.count x

def isSublistB : List Val → List Val → Bool
  | [], _ => true
  | _, [] => false
  | x :: xs, y :: ys => if x == y then isSublistB xs ys else isSublistB (x :: xs) ys

/-! ## `NoLoss`: the wrong function loses the element; the mirror does not -/

def lossIn : List (List Op) := [[.take], [.offer (.nat 1)]]

theorem wDrop_breaks : (runWith wDrop (.boundedConc 2) lossIn [(2, 0)] .cancelAll).map (fun o =>
    o.summary == .done (.succeeded .unit) && !subMultiB (offeredOf o.out) (removedOf o.out)) = some true := by
  decide +kernel

theorem drop_mirror_ok : (runWith henv (.boundedConc 2) lossIn [(2, 0)] .cancelAll).map (fun o =>
    o.summary == .done (.succeeded .unit) && subMultiB (offeredOf o.out) (removedOf o.out)) = some true := by
  decide +kernel

theorem wDropAsync_breaks : (runWith wDropAsync .unbounded lossIn [(2, 0)] .cancelAll).map (fun o =>
    o.summary == .done (.succeeded .unit) && !subMultiB (offeredOf o.out) (removedOf o.out)) = some true := by
  decide +kernel

theorem dropAsync_mirror_ok : (runWith henv .unbounded lossIn [(2, 0)] .cancelAll).map (fun o =>
    o.summary == .done (.succeeded .unit) && subMultiB (offeredOf o.out) (removedOf o.out)) = some true := by
  decide +kernel

/-! ## `NoDup` -/

def dupIn : List (List Op) := [[.offer (.nat 1), .take]]

theorem wDup_breaks : (runWith wDup (.boundedConc 2) dupIn [] (.join [0])).map (fun o =>
    !subMultiB (removedOf o.out) (allOffers dupIn)) = some true := by
  decide +kernel

theorem dup_mirror_ok : (runWith henv (.boundedConc 2) dupIn [] (.join [0])).map (fun o =>
    subMultiB (removedOf o.out) (allOffers dupIn)) = some true := by
  decide +kernel

theorem wDupAsync_breaks : (runWith wDupAsync (.bounded 2) dupIn [] (.join [0])).map (fun o =>
    !subMultiB (removedOf o.out) (allOffers dupIn)) = some true := by
  decide +kernel

theorem dupAsync_mirror_ok : (runWith henv (.bounded 2) dupIn [] (.join [0])).map (fun o =>
    subMultiB (removedOf o.out) (allOffers dupIn)) = some true := by
  decide +kernel

/-! ## `Fifo` -/

def fifoIn : List (List Op) := [[.offer (.nat 1), .offer (.nat 2), .tryTake]]

theorem wLifoConc_breaks : (runWith wLifoConc (.boundedConc 3) fifoIn [] (.join [0])).map (fun o =>
    !isSublistB ((removedOf o.out).filter (· ∈ offersOf (fifoIn.headD []))) (offersOf (fifoIn.headD []))) = some true := by
  decide +kernel

theorem wLifo_breaks : (runWith wLifo (.bounded 3) fifoIn [] (.join [0])).map (fun o =>
    !isSublistB ((removedOf o.out).filter (· ∈ offersOf (fifoIn.headD []))) (offersOf (fifoIn.headD []))) = some true := by
  decide +kernel

theorem fifo_mirror_ok : (runWith henv (.bounded 3) fifoIn [] (.join [0])).map (fun o =>
    isSublistB ((removedOf o.out).filter (· ∈ offersOf (fifoIn.headD []))) (offersOf (fifoIn.headD []))) = some true := by
  decide +kernel

/-! ## `NoDeadlock` -/

def hangIn : List (List Op) := [[.take]]

theorem wHangConc_breaks : (runWith wHangConc (.boundedConc 1) hangIn [(1, 0)] .cancelAll).map (fun o =>
    o.summary != .done (.succeeded .unit)) = some true := by
  decide +kernel

theorem hang_mirror_ok : (runWith henv (.boundedConc 1) hangIn [(1, 0)] .cancelAll).map (fun o =>
    o.summary == .done (.succeeded .unit)) = some true := by
  decide +kernel

theorem wHangAsync_breaks : (runWith wHangAsync .unbounded hangIn [(1, 0)] .cancelAll).map (fun o =>
    o.summary != .done (.succeeded .unit)) = some true := by
  decide +kernel

theorem hangAsync_mirror_ok : (runWith henv .unbounded hangIn [(1, 0)] .cancelAll).map (fun o =>
    o.summary == .done (.succeeded .unit)) = some true := by
  decide +kernel

/-! ## `TakerLiveness` -/

theorem wNoWake_breaks : (runWith wNoWake (.boundedConc 2) lossIn [] (.join [0])).map (fun o =>
    o.summary != .done (.succeeded .unit)) = some true := by
  decide +kernel

theorem wNoNotify_breaks : (runWith wNoNotify .unbounded lossIn [] (.join [0])).map (fun o =>
    o.summary != .done (.succeeded .unit)) = some true := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase7.QueueWrongFunction
