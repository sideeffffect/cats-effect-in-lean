import CatsEffectInLean.Props.Phase7.Queue

/-!
# Satisfiability witnesses of the `Queue` statements (decision 53)

For each statement and family: one concrete input that meets all hypotheses, and one run (fuel
3000, the FIFO `PChoice` list `[]`, kernel-checked) that reaches the interesting case. The
statements have no `WellFormed` hypothesis (the harness holds no user code), so each witness is
the run itself.

* Safety statements (`NoLoss`, `NoDup`, `Fifo`, `NoDeadlock`; mode `cancelAll`): a consumer with
  takes and a producer with offers; the plan cancels the consumer after 3 `cede`s while it waits
  for an element.
  * `Concurrent` (`boundedForConcurrent(1)`): consumer `take, take`, producer `offer 1, offer 2`.
    The consumer takes 1, is canceled while it waits; 2 stays in the queue and the drain removes
    it. Events: offered 1, took 1, offered 2, drained 2.
  * `Async` (`bounded(2)` = `BoundedAsyncQueue`): consumer `take, take, take`, producer
    `offer 1, offer 2`. The consumer takes 1 and 2 and is canceled while it waits for a third
    element. Events: offered 1, offered 2, took 1, took 2.
* `TakerLiveness` (mode `join [0]`): consumer `take`, producer `offer 1`; the consumer waits
  first, the offer wakes it. Events: offered 1, took 1. Kinds `boundedForConcurrent(1)` and
  `unbounded` (`UnboundedAsyncQueue`).
-/

namespace CatsEffectInLean.Proofs.Phase7.QueueWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Std.QueueFactory
open CatsEffectInLean.Props.Phase7.Queue

theorem exists_of_map {o? : Option Obs} {p : Obs → Bool} (h : o?.map p = some true) :
    ∃ o, o? = some o ∧ p o = true := by
  cases o? with
  | none => cases h
  | some o => exact ⟨o, rfl, by simpa using h⟩

/-- The interesting events of a safety run. -/
def concEvents : List (Nat × Val) := [(0, .nat 1), (1, .nat 1), (0, .nat 2), (4, .nat 2)]
def asyncEvents : List (Nat × Val) := [(0, .nat 1), (0, .nat 2), (1, .nat 1), (1, .nat 2)]
def liveEvents : List (Nat × Val) := [(0, .nat 1), (1, .nat 1)]

def concScripts : List (List Op) := [[.take, .take], [.offer (.nat 1), .offer (.nat 2)]]
def asyncScripts : List (List Op) := [[.take, .take, .take], [.offer (.nat 1), .offer (.nat 2)]]
def liveScripts : List (List Op) := [[.take], [.offer (.nat 1)]]

def concRun : Option Obs :=
  runObsP {} counterMaskModel henv 3000 [] (rootIO (.boundedConc 1) concScripts [(3, 0)] .cancelAll)

def asyncRun : Option Obs :=
  runObsP {} counterMaskModel henv 3000 [] (rootIO (.bounded 2) asyncScripts [(3, 0)] .cancelAll)

def concLiveRun : Option Obs :=
  runObsP {} counterMaskModel henv 3000 [] (rootIO (.boundedConc 1) liveScripts [] (.join [0]))

def asyncLiveRun : Option Obs :=
  runObsP {} counterMaskModel henv 3000 [] (rootIO .unbounded liveScripts [] (.join [0]))

theorem concRun_ok : concRun.map (fun o =>
    o.summary == .done (.succeeded .unit) && events o.out == concEvents) = some true := by
  decide +kernel

theorem asyncRun_ok : asyncRun.map (fun o =>
    o.summary == .done (.succeeded .unit) && events o.out == asyncEvents) = some true := by
  decide +kernel

theorem concLiveRun_ok : concLiveRun.map (fun o =>
    o.summary == .done (.succeeded .unit) && events o.out == liveEvents) = some true := by
  decide +kernel

theorem asyncLiveRun_ok : asyncLiveRun.map (fun o =>
    o.summary == .done (.succeeded .unit) && events o.out == liveEvents) = some true := by
  decide +kernel

theorem concKeep_bounded1 : ConcKeep (.boundedConc 1) := Or.inl ⟨1, by decide, rfl⟩
theorem asyncKeep_bounded2 : AsyncKeep (.bounded 2) := Or.inl ⟨2, by decide, by decide, rfl⟩
theorem asyncKeep_unbounded : AsyncKeep .unbounded := Or.inr rfl

/-- The safety witness of a family: hypotheses of `NoLoss`, `NoDup`, `Fifo`, `NoDeadlock` hold,
and a run reaches a canceled waiting consumer with offered elements. -/
def SafetyWitness (fam : QKind → Prop) (evs : List (Nat × Val)) : Prop :=
  ∃ k scripts plan, fam k ∧ (allOffers scripts).Nodup ∧ (scripts.filter takes).length ≤ 1 ∧
    ∃ o, runs k scripts plan .cancelAll o ∧ o.summary = .done (.succeeded .unit) ∧ events o.out = evs

/-- The liveness witness of a family: all hypotheses of `TakerLiveness` hold, and a run wakes a
waiting taker. -/
def LivenessWitness (fam : QKind → Prop) : Prop :=
  ∃ k scripts plan, fam k ∧
    (∀ s ∈ scripts, producer s ∨ consumer s) ∧
    (∀ p ∈ plan, ∀ s, scripts[p.2]? = some s → consumer s) ∧
    (scripts.map takeCount).sum ≤ (allOffers scripts).length ∧
    ∃ o, runs k scripts plan (.join ((List.range scripts.length).filter fun i =>
        match scripts[i]? with | some s => takes s | none => false)) o ∧
      o.summary = .done (.succeeded .unit) ∧ events o.out = liveEvents

theorem conc_satisfiable : SafetyWitness ConcKeep concEvents := by
  obtain ⟨o, ho, hp⟩ := exists_of_map concRun_ok
  simp only [Bool.and_eq_true, beq_iff_eq] at hp
  exact ⟨_, concScripts, [(3, 0)], concKeep_bounded1, by decide, by decide, o, ⟨3000, [], ho⟩, hp.1, hp.2⟩

theorem async_satisfiable : SafetyWitness AsyncKeep asyncEvents := by
  obtain ⟨o, ho, hp⟩ := exists_of_map asyncRun_ok
  simp only [Bool.and_eq_true, beq_iff_eq] at hp
  exact ⟨_, asyncScripts, [(3, 0)], asyncKeep_bounded2, by decide, by decide, o, ⟨3000, [], ho⟩, hp.1, hp.2⟩

/-- `ConcKeep` and `AsyncKeep` imply the `*Any` families (`NoDup`, `Fifo`, `NoDeadlock`). -/
theorem concAny_of_keep {k : QKind} (h : ConcKeep k) : ConcAny k := Or.inl h
theorem asyncAny_of_keep {k : QKind} (h : AsyncKeep k) : AsyncAny k := Or.inl h

theorem conc_any_satisfiable : SafetyWitness ConcAny concEvents := by
  obtain ⟨k, s, p, hk, h⟩ := conc_satisfiable
  exact ⟨k, s, p, concAny_of_keep hk, h⟩

theorem async_any_satisfiable : SafetyWitness AsyncAny asyncEvents := by
  obtain ⟨k, s, p, hk, h⟩ := async_satisfiable
  exact ⟨k, s, p, asyncAny_of_keep hk, h⟩

theorem liveScripts_shape : ∀ s ∈ liveScripts, producer s ∨ consumer s := by
  intro s hs
  simp only [liveScripts, List.mem_cons, List.mem_nil_iff, or_false] at hs
  rcases hs with rfl | rfl
  · exact Or.inr (by intro op h; simpa using h)
  · exact Or.inl (by intro op h; simp at h; exact ⟨_, h⟩)

theorem conc_live_satisfiable : LivenessWitness ConcKeep := by
  obtain ⟨o, ho, hp⟩ := exists_of_map concLiveRun_ok
  simp only [Bool.and_eq_true, beq_iff_eq] at hp
  exact ⟨_, liveScripts, [], concKeep_bounded1, liveScripts_shape, by simp, by decide,
    o, ⟨3000, [], ho⟩, hp.1, hp.2⟩

theorem async_live_satisfiable : LivenessWitness AsyncKeep := by
  obtain ⟨o, ho, hp⟩ := exists_of_map asyncLiveRun_ok
  simp only [Bool.and_eq_true, beq_iff_eq] at hp
  exact ⟨_, liveScripts, [], asyncKeep_unbounded, liveScripts_shape, by simp, by decide,
    o, ⟨3000, [], ho⟩, hp.1, hp.2⟩

end CatsEffectInLean.Proofs.Phase7.QueueWitness
