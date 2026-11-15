import CatsEffectInLean.Proofs.Phase7.QueueBatteryDefs

/-!
# Decision 63 battery for `Queue`: `Synchronous` (part of the `Concurrent` family)

`Synchronous` needs a partner for `offer` and `take`, so its rows use two-fiber inputs and the
statements `TakerLiveness` (with the join outcomes, review batch 12 H3), `NoDup`, `NoLoss`; the
one-fiber rows use `SeqSpec`. FIFO schedule, fuel 3000, kernel-checked. The mirror meets every
claim on the same inputs (`sync_*_mirror`).

`tryTake` `drops` (it answers `None` while an offerer waits, without effect) breaks statement 8
(`syncTryTakeHandoff`, FIFO schedule: the offerer is registered when `tryTake` runs).
-/

namespace CatsEffectInLean.Proofs.Phase7.QueueBattery

open CatsEffectInLean.Model
open CatsEffectInLean.Std.QueueFactory
open CatsEffectInLean.Props.Phase7.Queue

def subM (a b : List Val) : Bool := a.all fun x => a.count x ≤ b.count x

/-- `TakerLiveness` (with `JoinsSucceeded`, no plan) as a `Bool`. -/
def liveB (sc : List (List Op)) (o : Obs) : Bool :=
  (o.summary == .done (.succeeded .unit) && (takers sc).all fun i =>
    (events o.out).any fun e => e.1 == evJoined && e.2.1 == i && (match e.2.2 with | .ocSucceeded _ => true | _ => false)) ||
  (o.summary == .blocked && subM (offeredOf o.out) (removedOf o.out) && subM (startedOf o.out) (offeredOf o.out))

def noDupB (sc : List (List Op)) (o : Obs) : Bool := subM (removedOf o.out) (allOffers sc)
def noLossB (o : Obs) : Bool := o.summary != .done (.succeeded .unit) || subM (offeredOf o.out) (removedOf o.out)

def sr (e : UserEnv) (sc : List (List Op)) (p : List (Nat × Nat)) (m : Mode) : Option Obs :=
  runObsP {} counterMaskModel e 3000 [] (rootIO .synchronous sc p m)

def offerIn : List (List Op) := [[.take], [.take], [.offer (.nat 1)]]
def takeIn : List (List Op) := [[.take], [.offer (.nat 1)]]
def tryOfferIn : List (List Op) := [[.take], [.take], [.tryOffer (.nat 1)]]
def tryTakeIn : List (List Op) := [[.offer (.nat 1)], [.offer (.nat 2)], [.tryTake]]

def oneSpec (e : UserEnv) (s : List Op) : Option Bool :=
  (sr e [s] [] (.join [0])).map (specB .synchronous s)

theorem sync_offer_mirror : (sr henv offerIn [] (.join [0, 1])).map (fun o => liveB offerIn o && noDupB offerIn o) = some true := by
  decide +kernel
theorem sync_offer_raises : (sr (battery .offer .raises) offerIn [] (.join [0, 1])).map (liveB offerIn) = some false := by
  decide +kernel
theorem sync_offer_hangs : (sr (battery .offer .hangs) offerIn [] (.join [0, 1])).map (liveB offerIn) = some false := by
  decide +kernel
theorem sync_offer_drops : (sr (battery .offer .drops) offerIn [] (.join [0, 1])).map (liveB offerIn) = some false := by
  decide +kernel
theorem sync_offer_doubles : (sr (battery .offer .doubles) offerIn [] (.join [0, 1])).map (noDupB offerIn) = some false := by
  decide +kernel

theorem sync_take_mirror : (sr henv takeIn [] (.join [0])).map (fun o => liveB takeIn o && noDupB takeIn o) = some true := by
  decide +kernel
theorem sync_take_raises : (sr (battery .take .raises) takeIn [] (.join [0])).map (liveB takeIn) = some false := by
  decide +kernel
theorem sync_take_hangs : (sr (battery .take .hangs) takeIn [] (.join [0])).map (liveB takeIn) = some false := by
  decide +kernel
theorem sync_take_drops : (sr (battery .take .drops) takeIn [] (.join [0])).map (noDupB takeIn) = some false := by
  decide +kernel
theorem sync_take_doubles : (sr (battery .take .doubles) takeIn [] (.join [0])).map (liveB takeIn) = some false := by
  decide +kernel

theorem sync_tryOffer_mirror : oneSpec henv [.tryOffer (.nat 1)] = some true ∧
    (sr henv tryOfferIn [] (.join [0, 1])).map (noDupB tryOfferIn) = some true := by
  decide +kernel
theorem sync_tryOffer_raises : oneSpec (battery .tryOffer .raises) [.tryOffer (.nat 1)] = some false := by
  decide +kernel
theorem sync_tryOffer_hangs : oneSpec (battery .tryOffer .hangs) [.tryOffer (.nat 1)] = some false := by
  decide +kernel
theorem sync_tryOffer_drops : oneSpec (battery .tryOffer .drops) [.tryOffer (.nat 1)] = some false := by
  decide +kernel
theorem sync_tryOffer_doubles : (sr (battery .tryOffer .doubles) tryOfferIn [] (.join [0, 1])).map (noDupB tryOfferIn) = some false := by
  decide +kernel

theorem sync_tryTake_mirror : oneSpec henv [.tryTake] = some true ∧
    (sr henv tryTakeIn [(3, 2)] .cancelAll).map noLossB = some true := by
  decide +kernel
theorem sync_tryTake_raises : oneSpec (battery .tryTake .raises) [.tryTake] = some false := by
  decide +kernel
theorem sync_tryTake_hangs : oneSpec (battery .tryTake .hangs) [.tryTake] = some false := by
  decide +kernel
theorem sync_tryTake_doubles : (sr (battery .tryTake .doubles) tryTakeIn [(3, 2)] .cancelAll).map noLossB = some false := by
  decide +kernel

/-- The claim of statement 8 as a `Bool` (element `1`, fuel 3000). -/
def handoffB (e : UserEnv) : Option Bool :=
  (runObsP {} counterMaskModel e 3000 [] (handoffRoot (.nat 1))).map fun o =>
    (events o.out).contains (evTryTook, 1, .some (.nat 1)) && (events o.out).contains (evJoined, 0, .ocSucceeded .unit) &&
      (events o.out).contains (evJoined, 1, .ocSucceeded .unit) && o.summary == .done (.succeeded .unit)

theorem sync_tryTake_handoff_mirror : handoffB henv = some true := by
  decide +kernel
theorem sync_tryTake_drops : handoffB (battery .tryTake .drops) = some false := by
  decide +kernel

theorem sync_size_mirror : oneSpec henv [.size] = some true := by
  decide +kernel
theorem sync_size_raises : oneSpec (battery .size .raises) [.size] = some false := by
  decide +kernel
theorem sync_size_hangs : oneSpec (battery .size .hangs) [.size] = some false := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase7.QueueBattery
