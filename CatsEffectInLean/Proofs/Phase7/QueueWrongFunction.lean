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
| `wLifoConc`: `AbstractQueue#tryTake` takes the last element | `concFifo` | `boundedForConcurrent(3)`, `[[offer 1, offer 2, tryTake, tryTake]]` |
| `wLifo`: `BaseBoundedAsyncQueue#tryTake` takes the last element | `asyncFifo` | `bounded(3)`, same |
| `wLastIfWaiters`: `AbstractQueue#take` takes the last element when another taker waits (review 11a F1) | `concFifo` | `boundedForConcurrent(2)`, `[[take, take], [take], [take], [offer 1, offer 2]]`, plan `[(1, 1)]` |
| `wLastIfWaitersAsync`: the same in `BaseBoundedAsyncQueue#take` | `asyncFifo` | `bounded(3)`, same |
| `wNoPassOn`: no `cleanup`/`notifyNextTaker` pass-on (review 11a L1) | `concTakerLiveness` | `boundedForConcurrent(2)`, `[[take], [take], [offer 1]]`, plan `[(1, 0)]`, join `[0, 1]` |
| `wNoAnywayU`: no `notifyAnyway` in `UnboundedAsyncQueue#take` | `asyncTakerLiveness` | `unbounded`, same |
| `wHangConc`: the `cleanup` of a canceled `AbstractQueue#take` waits for its own taker | `concNoDeadlock` | `boundedForConcurrent(1)`, `[[take]]`, plan `[(1, 0)]` |
| `wHangAsync`: `UnboundedAsyncQueue#take` waits in `get` without `poll` (cannot be canceled) | `asyncNoDeadlock` | `unbounded`, same |
| `wNoWake`: `AbstractQueue#offer` enqueues but does not complete the taker | `concTakerLiveness` | `boundedForConcurrent(2)`, `[[take], [offer 1]]`, join `[0]` |
| `wNoNotify`: `UnboundedAsyncQueue#offer` puts but does not notify | `asyncTakerLiveness` | `unbounded`, same |
| `wLifo` on the `Async` side only | `twinSeq` | `(boundedForConcurrent(3), bounded(3))`, one fiber `[offer 1, offer 2, tryTake]` |
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

open QueueConcurrent in
/-- Review batch 11a F1: `AbstractQueue#take` takes the last element when another taker waits. -/
def wLastIfWaiters : UserEnv := wrap fun id _ v =>
  match QC.ofId? id with
  | some (.takeMod o _ _ _) =>
    match absState v o with
    | some (_, _, s, st) =>
      match st.takers, st.queue.reverse, st.offerers with
      | _ :: _, a :: rest, [] =>
        some { effects := [.writeRef s { st with queue := rest.reverse, size := st.size - 1 }.toVal], out := .ret (dPure a) }
      | _, _, _ => none
    | none => none
  | _ => none

open QueueAsync in
/-- The `Async` analogue: `BaseBoundedAsyncQueue#take` takes the last element when the takers list
holds a live cell. -/
def wLastIfWaitersAsync : UserEnv := wrap fun id _ v =>
  match QA.ofId? id with
  | some (.bTakeThunk o _ _) =>
    match Obj.ofId? o with
    | some (.bnd _ _ b) =>
      if (waitersOf v (b + 1)).cells.any (fun c => c.2.isSome) then
        match (bufOf v b).reverse with
        | a :: rest => some { effects := .writeRef b (listV rest.reverse) :: notifyAt (b + 2) (waitersOf v (b + 2)),
                              out := .ret (dPure a) }
        | [] => none
      else none
    | _ => none
  | _ => none

open QueueConcurrent in
/-- Review batch 11a L1: no cancel pass-on. `cleanup` of a canceled `take` only removes its taker,
and `notifyNextTaker` does nothing. -/
def wNoPassOn : UserEnv := wrap fun id _ v =>
  match QC.ofId? id with
  | some (.cleanupTake o t) =>
    match absState v o with
    | some (_, _, s, st) => some { effects := [.writeRef s { st with takers := dropId t st.takers }.toVal], out := .ret dUnit }
    | none => none
  | some (.notifyNext _) => some { out := .ret dUnit }
  | _ => none

open QueueAsync in
/-- The `Async` analogue: `notifyAnyway` of `UnboundedAsyncQueue#take` does nothing. -/
def wNoAnywayU : UserEnv := wrap fun id _ _ =>
  match QA.ofId? id with
  | some (.uNotify _) => some { out := .ret .unit }
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

/-- The `Fifo` claim as a `Bool` for removers `0..5` and the drain (enough for the inputs here). -/
def fifoOKB (sc : List (List Op)) (o : Obs) : Bool :=
  ((List.range 6).map some ++ [none]).all fun c => sc.all fun s =>
    isSublistB ((removedBy o.out c).filter (· ∈ offersOf s)) (offersOf s)

/-- One script takes twice from its own two offers. -/
def fifoIn : List (List Op) := [[.offer (.nat 1), .offer (.nat 2), .tryTake, .tryTake]]

theorem wLifoConc_breaks : (runWith wLifoConc (.boundedConc 3) fifoIn [] (.join [0])).map (fun o =>
    !fifoOKB fifoIn o) = some true := by
  decide +kernel

theorem wLifo_breaks : (runWith wLifo (.bounded 3) fifoIn [] (.join [0])).map (fun o =>
    !fifoOKB fifoIn o) = some true := by
  decide +kernel

theorem fifo_mirror_ok : (runWith henv (.bounded 3) fifoIn [] (.join [0])).map (fun o =>
    fifoOKB fifoIn o) = some true := by
  decide +kernel

/-- Review batch 11a F1: three consumers and one producer; the plan cancels consumer 1 after one
`cede`. With `wLastIfWaiters` consumer 0 removes `2` and then `1`. -/
def fifoMulti : List (List Op) := [[.take, .take], [.take], [.take], [.offer (.nat 1), .offer (.nat 2)]]

theorem wLastIfWaiters_breaks : (runWith wLastIfWaiters (.boundedConc 2) fifoMulti [(1, 1)] .cancelAll).map (fun o =>
    !fifoOKB fifoMulti o) = some true := by
  decide +kernel

theorem lastIfWaiters_mirror_ok : (runWith henv (.boundedConc 2) fifoMulti [(1, 1)] .cancelAll).map (fun o =>
    fifoOKB fifoMulti o) = some true := by
  decide +kernel

theorem wLastIfWaitersAsync_breaks : (runWith wLastIfWaitersAsync (.bounded 3) fifoMulti [(1, 1)] .cancelAll).map (fun o =>
    !fifoOKB fifoMulti o) = some true := by
  decide +kernel

theorem lastIfWaitersAsync_mirror_ok : (runWith henv (.bounded 3) fifoMulti [(1, 1)] .cancelAll).map (fun o =>
    fifoOKB fifoMulti o) = some true := by
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

/-- The `TakerLiveness` claim as a `Bool`: `Succeeded`, or `blocked` with nothing to give. -/
def liveOKB (o : Obs) : Bool :=
  o.summary == .done (.succeeded .unit) ||
    (o.summary == .blocked && subMultiB (offeredOf o.out) (removedOf o.out) &&
      subMultiB (startedOf o.out) (offeredOf o.out))

theorem wNoWake_breaks : (runWith wNoWake (.boundedConc 2) lossIn [] (.join [0])).map (fun o =>
    !liveOKB o) = some true := by
  decide +kernel

theorem wNoNotify_breaks : (runWith wNoNotify .unbounded lossIn [] (.join [0])).map (fun o =>
    !liveOKB o) = some true := by
  decide +kernel

/-- Review batch 11a L1: the canonical lost wakeup. Two consumers wait, one offer wakes consumer 0,
the plan cancels consumer 0 (after one `cede`); without the pass-on, consumer 1 waits forever while
element 1 is in the queue. Takes (2) exceed offers (1): the old count hypothesis excluded this. -/
def passOnIn : List (List Op) := [[.take], [.take], [.offer (.nat 1)]]

theorem wNoPassOn_breaks : (runWith wNoPassOn (.boundedConc 2) passOnIn [(1, 0)] (.join [0, 1])).map (fun o =>
    !liveOKB o) = some true := by
  decide +kernel

theorem passOn_mirror_ok : (runWith henv (.boundedConc 2) passOnIn [(1, 0)] (.join [0, 1])).map (fun o =>
    liveOKB o) = some true := by
  decide +kernel

theorem wNoAnywayU_breaks : (runWith wNoAnywayU .unbounded passOnIn [(1, 0)] (.join [0, 1])).map (fun o =>
    !liveOKB o) = some true := by
  decide +kernel

theorem passOnAsync_mirror_ok : (runWith henv .unbounded passOnIn [(1, 0)] (.join [0, 1])).map (fun o =>
    liveOKB o) = some true := by
  decide +kernel

/-! ## `twinSeq`: a broken `Async` side gives a trace that the `Concurrent` side never gives -/

theorem wLifo_twin_breaks : (runWith henv (.boundedConc 3) fifoIn [] (.join [0])).map (fun o => events o.out) ≠
    (runWith wLifo (.bounded 3) fifoIn [] (.join [0])).map (fun o => events o.out) := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase7.QueueWrongFunction
