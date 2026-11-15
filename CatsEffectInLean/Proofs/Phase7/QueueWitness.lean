import CatsEffectInLean.Props.Phase7.Queue

/-!
# Satisfiability witnesses of the `Queue` statements (decision 53)

For each statement and family: one concrete input that meets all hypotheses, and one run (fuel
3000, the FIFO `PChoice` list `[]`, kernel-checked) that reaches the interesting case. The
statements have no `WellFormed` hypothesis (the harness holds no user code), so each witness is
the run itself. Events are (tag, script index, value); tag 6 = an `offer` started, 0 = offered,
1 = took, 4 = drained.

* Safety statements (`NoLoss`, `NoDup`, `Fifo`, `NoDeadlock`; mode `cancelAll`): a consumer with
  takes and a producer with offers; the plan cancels the consumer after 3 `cede`s while it waits
  for an element.
  * `Concurrent` (`boundedForConcurrent(1)`): consumer `take, take`, producer `offer 1, offer 2`.
    The consumer takes 1, is canceled while it waits; 2 stays in the queue and the drain removes
    it.
  * `Async` (`bounded(2)` = `BoundedAsyncQueue`): consumer `take, take, take`, producer
    `offer 1, offer 2`. The consumer takes 1 and 2 and is canceled while it waits for a third
    element.
* `TakerLiveness` (review batch 11a: no count hypothesis), inputs `[[take], [take], [offer 1]]`,
  join `[0, 1]`, kinds `boundedForConcurrent(2)` and `unbounded`:
  * the pass-on: plan `[(1, 0)]` cancels consumer 0 after `offer 1` woke it; consumer 1 takes 1
    and the run ends `Succeeded` (takes 2 > offers 1, outside the old statement);
  * the allowed block (`QuietBlock`): no plan; consumer 0 takes 1, consumer 1 waits forever on an
    empty queue, every offer returned and was removed: the run stops `blocked`.
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
def concEvents : List (Nat × Nat × Val) :=
  [(6, 1, .nat 1), (0, 1, .nat 1), (6, 1, .nat 2), (1, 0, .nat 1), (0, 1, .nat 2), (4, 0, .nat 2)]
def asyncEvents : List (Nat × Nat × Val) :=
  [(6, 1, .nat 1), (0, 1, .nat 1), (6, 1, .nat 2), (0, 1, .nat 2), (1, 0, .nat 1), (1, 0, .nat 2)]
/-- Consumer 0 is canceled after the wakeup; consumer 1 takes 1. -/
def passOnEvents : List (Nat × Nat × Val) := [(6, 2, .nat 1), (0, 2, .nat 1), (1, 1, .nat 1)]
/-- Consumer 0 takes 1; consumer 1 waits on an empty queue. -/
def quietEvents : List (Nat × Nat × Val) := [(6, 2, .nat 1), (0, 2, .nat 1), (1, 0, .nat 1)]

def concScripts : List (List Op) := [[.take, .take], [.offer (.nat 1), .offer (.nat 2)]]
def asyncScripts : List (List Op) := [[.take, .take, .take], [.offer (.nat 1), .offer (.nat 2)]]
def liveScripts : List (List Op) := [[.take], [.take], [.offer (.nat 1)]]

def concRun : Option Obs :=
  runObsP {} counterMaskModel henv 3000 [] (rootIO (.boundedConc 1) concScripts [(3, 0)] .cancelAll)

def asyncRun : Option Obs :=
  runObsP {} counterMaskModel henv 3000 [] (rootIO (.bounded 2) asyncScripts [(3, 0)] .cancelAll)

def liveRun (k : QKind) (plan : List (Nat × Nat)) : Option Obs :=
  runObsP {} counterMaskModel henv 3000 [] (rootIO k liveScripts plan (.join [0, 1]))

theorem concRun_ok : concRun.map (fun o =>
    o.summary == .done (.succeeded .unit) && events o.out == concEvents) = some true := by
  decide +kernel

theorem asyncRun_ok : asyncRun.map (fun o =>
    o.summary == .done (.succeeded .unit) && events o.out == asyncEvents) = some true := by
  decide +kernel

theorem concPassOn_ok : (liveRun (.boundedConc 2) [(1, 0)]).map (fun o =>
    o.summary == .done (.succeeded .unit) && events o.out == passOnEvents) = some true := by
  decide +kernel

theorem asyncPassOn_ok : (liveRun .unbounded [(1, 0)]).map (fun o =>
    o.summary == .done (.succeeded .unit) && events o.out == passOnEvents) = some true := by
  decide +kernel

theorem concQuiet_ok : (liveRun (.boundedConc 2) []).map (fun o =>
    o.summary == .blocked && events o.out == quietEvents) = some true := by
  decide +kernel

theorem asyncQuiet_ok : (liveRun .unbounded []).map (fun o =>
    o.summary == .blocked && events o.out == quietEvents) = some true := by
  decide +kernel

theorem concKeep_bounded1 : ConcKeep (.boundedConc 1) := Or.inl ⟨1, by decide, rfl⟩
theorem concKeep_bounded2 : ConcKeep (.boundedConc 2) := Or.inl ⟨2, by decide, rfl⟩
theorem asyncKeep_bounded2 : AsyncKeep (.bounded 2) := Or.inl ⟨2, by decide, by decide, rfl⟩
theorem asyncKeep_unbounded : AsyncKeep .unbounded := Or.inr rfl

/-- The safety witness of a family: the hypotheses of `NoLoss`, `NoDup`, `Fifo`, `NoDeadlock` hold,
and a run reaches a canceled waiting consumer with offered elements. -/
def SafetyWitness (fam : QKind → Prop) (evs : List (Nat × Nat × Val)) : Prop :=
  ∃ k scripts plan, fam k ∧ (allOffers scripts).Nodup ∧
    ∃ o, runs k scripts plan .cancelAll o ∧ o.summary = .done (.succeeded .unit) ∧ events o.out = evs

/-- The liveness witness of a family: the hypotheses of `TakerLiveness` hold for `liveScripts`, one
run ends `Succeeded` after a canceled consumer passed its wakeup on, and one run stops in an allowed
block (`QuietBlock`). -/
def LivenessWitness (fam : QKind → Prop) : Prop :=
  ∃ k plan, fam k ∧
    (∀ s ∈ liveScripts, producer s ∨ consumer s) ∧
    (∀ p ∈ plan, ∀ s, liveScripts[p.2]? = some s → consumer s) ∧
    (List.range liveScripts.length).filter (fun i =>
        match liveScripts[i]? with | some s => takes s | none => false) = [0, 1] ∧
    (∃ o, runs k liveScripts plan (.join [0, 1]) o ∧ o.summary = .done (.succeeded .unit) ∧
      events o.out = passOnEvents) ∧
    (∃ o, runs k liveScripts [] (.join [0, 1]) o ∧ QuietBlock o ∧ events o.out = quietEvents)

theorem conc_satisfiable : SafetyWitness ConcKeep concEvents := by
  obtain ⟨o, ho, hp⟩ := exists_of_map concRun_ok
  simp only [Bool.and_eq_true, beq_iff_eq] at hp
  exact ⟨_, concScripts, [(3, 0)], concKeep_bounded1, by decide, o, ⟨3000, [], ho⟩, hp.1, hp.2⟩

theorem async_satisfiable : SafetyWitness AsyncKeep asyncEvents := by
  obtain ⟨o, ho, hp⟩ := exists_of_map asyncRun_ok
  simp only [Bool.and_eq_true, beq_iff_eq] at hp
  exact ⟨_, asyncScripts, [(3, 0)], asyncKeep_bounded2, by decide, o, ⟨3000, [], ho⟩, hp.1, hp.2⟩

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
  rcases hs with rfl | rfl | rfl
  · exact Or.inr (by intro op h; simpa using h)
  · exact Or.inr (by intro op h; simpa using h)
  · exact Or.inl (by intro op h; simp at h; exact ⟨_, h⟩)

theorem livePlan_consumer : ∀ p ∈ [(1, 0)], ∀ s, liveScripts[p.2]? = some s → consumer s := by
  intro p hp s hs
  simp only [List.mem_cons, List.mem_nil_iff, or_false] at hp
  subst hp
  simp [liveScripts] at hs
  subst hs
  intro op h; simpa using h

/-- The `QuietBlock` of a run with these events: offered `[1]`, removed `[1]`, started `[1]`. -/
theorem quiet_of_events {o : Obs} (hb : o.summary = .blocked) (he : events o.out = quietEvents) :
    QuietBlock o := by
  refine ⟨hb, ?_, ?_⟩
  · intro x hx
    simp [offeredOf, removedOf, he, quietEvents] at hx ⊢
  · intro x hx
    simp [startedOf, offeredOf, he, quietEvents] at hx ⊢

theorem conc_live_satisfiable : LivenessWitness ConcKeep := by
  obtain ⟨o, ho, hp⟩ := exists_of_map concPassOn_ok
  obtain ⟨o', ho', hp'⟩ := exists_of_map concQuiet_ok
  simp only [Bool.and_eq_true, beq_iff_eq] at hp hp'
  exact ⟨_, [(1, 0)], concKeep_bounded2, liveScripts_shape, livePlan_consumer, by decide,
    ⟨o, ⟨3000, [], ho⟩, hp.1, hp.2⟩, ⟨o', ⟨3000, [], ho'⟩, quiet_of_events hp'.1 hp'.2, hp'.2⟩⟩

theorem async_live_satisfiable : LivenessWitness AsyncKeep := by
  obtain ⟨o, ho, hp⟩ := exists_of_map asyncPassOn_ok
  obtain ⟨o', ho', hp'⟩ := exists_of_map asyncQuiet_ok
  simp only [Bool.and_eq_true, beq_iff_eq] at hp hp'
  exact ⟨_, [(1, 0)], asyncKeep_unbounded, liveScripts_shape, livePlan_consumer, by decide,
    ⟨o, ⟨3000, [], ho⟩, hp.1, hp.2⟩, ⟨o', ⟨3000, [], ho'⟩, quiet_of_events hp'.1 hp'.2, hp'.2⟩⟩

/-! ## Statement 6 (`twinSeq`): both sides give the same nontrivial trace -/

/-- One fiber: `offer 1, offer 2, tryOffer 3, tryTake, size, take, tryOffer 4, tryTake` (capacity 2:
the queue is full at `tryOffer 3`). -/
def twinScript : List Op :=
  [.offer (.nat 1), .offer (.nat 2), .tryOffer (.nat 3), .tryTake, .size, .take, .tryOffer (.nat 4), .tryTake]

def twinEvents : List (Nat × Nat × Val) :=
  [(6, 0, .nat 1), (0, 0, .nat 1), (6, 0, .nat 2), (0, 0, .nat 2), (3, 0, .pair (.nat 3) (.bool false)),
   (2, 0, .some (.nat 1)), (5, 0, .nat 1), (1, 0, .nat 2), (3, 0, .pair (.nat 4) (.bool true)),
   (2, 0, .some (.nat 4))]

def twinRun (k : QKind) : Option Obs := runObsP {} counterMaskModel henv 3000 [] (rootIO k [twinScript] [] (.join [0]))

theorem twinRun_conc_ok : (twinRun (.boundedConc 2)).map (fun o =>
    o.summary == .done (.succeeded .unit) && events o.out == twinEvents) = some true := by
  decide +kernel

theorem twinRun_async_ok : (twinRun (.bounded 2)).map (fun o =>
    o.summary == .done (.succeeded .unit) && events o.out == twinEvents) = some true := by
  decide +kernel

/-- The hypotheses of `twinSeq` hold for capacity 2 and the bounded pair, and both sides reach the
same nontrivial trace (full queue, `tryOffer` false, FIFO, `size`). -/
theorem twinSeq_satisfiable :
    ∃ cap, 2 ≤ cap ∧ cap < asyncLimit ∧ ∃ p ∈ twinPairs cap, ∃ o o', runs p.1 [twinScript] [] (.join [0]) o ∧
      runs p.2 [twinScript] [] (.join [0]) o' ∧ o.summary = o'.summary ∧ events o.out = twinEvents ∧
      events o'.out = twinEvents := by
  obtain ⟨o, ho, hp⟩ := exists_of_map twinRun_conc_ok
  obtain ⟨o', ho', hp'⟩ := exists_of_map twinRun_async_ok
  simp only [Bool.and_eq_true, beq_iff_eq] at hp hp'
  exact ⟨2, by decide, by decide, _, List.mem_cons_self .., o, o', ⟨3000, [], ho⟩, ⟨3000, [], ho'⟩,
    hp.1.trans hp'.1.symm, hp.2, hp'.2⟩

end CatsEffectInLean.Proofs.Phase7.QueueWitness
