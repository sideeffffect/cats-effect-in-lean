import CatsEffectInLean.Props.Phase7.Semaphore

/-!
# Satisfiability witnesses of the `Semaphore`/`Mutex` statements (decision 53)

For each open statement: one concrete input that meets all hypotheses together, and one run (fuel
and `PChoice` list, kernel-checked) that reaches the interesting case. User code (statements 1, 3,
4, 8) is the constant table `cu`: id 2 is `_ => IO.pure(0)` (no handle), so `WellFormed` holds.

* `semNoLostPermit_satisfiable`: `Semaphore(1)`, uses `[permit g, acqRel 1]`, acts
  `[cede, cancel 1, join 0]`: a run ends `Succeeded((1, 1))`.
* `semNoDeadlock_satisfiable`: `Semaphore(1)`, `[permit (cede, then ()), acqRel 1, tryRel 1]`, acts
  `[join 0, cancel 1, join 2, release 1]`: a run ends `Succeeded((2, 2))`, and the joins of uses 0
  and 2 recorded `Succeeded`. Regressions of review batch 11b: `fatal_regression` (H1) and
  `w1_breaks` (W1, wrong function "`acquireN(n ≥ 2)` always raises").
* `semAtMostK_satisfiable`: `Semaphore(1)`, two counted uses, both joined: a run with highest
  count 1 (two fibers wanted the permit, one at a time).
* `mutexMutualExclusion_satisfiable`: the same with `Mutex`.
* `mutexNoDeadlock_satisfiable`: `Mutex`, `[permit (cede, then ()), permit canceled]`, acts
  `[join 0, join 1]`: a run ends `Succeeded(())`, and the join of use 0 recorded `Succeeded`.
* `semFifo_satisfiable`: `n = [2, 1]`, `r = 2`: a run ends `Succeeded(-1)` (the first request is
  served, the second waits).
* `mutexSemaphoreTwin_satisfiable`: two counted uses: the mutex and the `Semaphore(1)` program each
  have a run with the same root outcome and trace.
-/

namespace CatsEffectInLean.Proofs.Phase7.SemaphoreWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Semaphore
open CatsEffectInLean.Props.Phase7.Semaphore

/-! ## Constant user code: id 2 is `_ => IO.pure(0)` -/

def cR : Nat → UserResult
  | 1 => { out := .prog (.pure (.nat 0)) }
  | _ => { out := .throw { code := 0 } }

def cu : UserEnv where
  call id _ _ := cR (id / 2)

theorem env_even (u : UserEnv) (id : Nat) (hid : id % 2 = 0) (a : Val) (v : View) :
    (env u).callV id a v = u.callV id a v := by
  have h1 : SL.ofId? id = none := by simp [SL.ofId?, isLibId, hid]
  have h2 : Mutex.ML.ofId? id = none := by simp [Mutex.ML.ofId?, isLibId, hid]
  have h3 : Bracket.BLam.ofId? id = none := Bracket.BLam.ofId?_even hid
  have h4 : HS.ofId? id = none := by simp [HS.ofId?, isLibId, hid]
  show Mutex.dispatch (harnessed u) id a v = _
  simp [Mutex.dispatch, Mutex.dispatch.go, h1, h2, h3, harnessed, h4]

theorem cu_even (id : Nat) (hid : id % 2 = 0) (a : Val) (v : View) : (env cu).callV id a v = cR (id / 2) := by
  rw [env_even _ id hid]; rfl

theorem cR_ok (n : Nat) (R : Handle → Prop) (v : View) : WF.ResultOK semLib R v (cR n) := by
  match n with
  | 0 | 1 => simp [cR, WF.ResultOK, WF.EffectsOK, WF.OutOK, WF.progOK, WF.subA, Val.handles]
  | _ + 2 => simp [cR, WF.ResultOK, WF.EffectsOK, WF.OutOK]

theorem constOpaque (e : UserEnv) (he : ∀ id, id % 2 = 0 → ∀ a v, e.callV id a v = cR (id / 2)) :
    WF.PollOpaque e := by
  refine WF.pollOpaque_of_const e (fun id => cR (id / 2)) [2] { out := .throw { code := 0 } }
    (fun id arg v hid => he id hid arg v) (by decide +kernel) ?_ ?_ (fun _ _ => rfl)
  · intro id hid hk
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hk
    obtain h | h : id / 2 = 0 ∨ 2 ≤ id / 2 := by omega
    · simp only [h]; rfl
    · obtain ⟨k, hk⟩ := Nat.exists_eq_add_of_le h
      simp only [hk, show 2 + k = k + 2 by omega]; rfl
  · intro σ _ k hk
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hk
    subst hk; rfl

theorem wfConst (p : IO) (hp : WF.progOK semLib (fun h => ([] : List Handle).contains h) p = true) :
    WellFormed semLib [] (env cu) p :=
  ⟨hp, fun id hid arg v => ⟨fun w _ => by rw [cu_even id hid, cu_even id hid],
    by rw [cu_even id hid]; exact cR_ok _ _ _⟩, constOpaque _ cu_even⟩

theorem exists_of_map {o? : Option Obs} {p : Obs → Bool} (h : o?.map p = some true) :
    ∃ o, o? = some o ∧ p o = true := by
  cases o? with
  | none => cases h
  | some o => exact ⟨o, rfl, by simpa using h⟩

/-! ## Statement 1 -/

def us1 : List Use := [.permit 2, .acqRel 1]
def as1 : List Act := [.cede, .cancel 1, .join 0]

def run1 : Option Obs := runObsP {} counterMaskModel (env cu) 3000 [] (lockRoot (.sem 1) us1 as1)

theorem run1_ok : run1.map (fun o => o.summary == .done (.succeeded (.pair (.nat 1) (.int 1)))) = some true := by
  decide +kernel

theorem semNoLostPermit_satisfiable :
    ∃ (u : UserEnv) (k : Nat) (us : List Use) (as : List Act),
      AllEnded us.length as ∧ WellFormed semLib [] (env u) (lockRoot (.sem k) us as) ∧
      ∃ o, outcomesP {} counterMaskModel (env u) (lockRoot (.sem k) us as) o ∧
        o.summary = .done (.succeeded (.pair (.nat 1) (.int 1))) := by
  obtain ⟨o, ho, hp⟩ := exists_of_map run1_ok
  refine ⟨cu, 1, us1, as1, ?_, wfConst _ (by decide +kernel), o, ⟨3000, [], ho⟩, by simpa using hp⟩
  intro i hi
  simp only [us1, List.length_cons, List.length_nil] at hi
  match i, hi with
  | 0, _ => exact .inr (by decide)
  | 1, _ => exact .inl (by decide)

/-! ## Statement 2 -/

def bus2 : List BUse := [.permit 1 (.ok .unit), .acqRel 1, .tryRel 1]
def as2 : List Act := [.join 0, .cancel 1, .join 2, .release 1]

def run2 : Option Obs :=
  runObsP {} counterMaskModel (env behaved) 3000 [] (lockRoot (.sem 1) (bus2.map BUse.toUse) as2)

theorem run2_ok : run2.map (fun o => o.summary == .done (.succeeded (.pair (.nat 2) (.int 2))) &&
    o.out.contains (joinRecV 0 (.ocSucceeded .unit)) && o.out.contains (joinRecV 2 (.ocSucceeded .unit))) = some true := by
  decide +kernel

/-- The interesting case of the new conclusion (review batch 11b): a run that ends `Succeeded`, with
`available = k + released`, in which the two joined uses that must succeed (`permit` with an `ok`
section, `tryRel`) recorded `Succeeded` (and the canceled `acqRel` is not one of them). -/
theorem semNoDeadlock_satisfiable :
    ∃ (k : Nat) (bus : List BUse) (as : List Act),
      AllEnded bus.length as ∧ (∀ b ∈ bus, b.need ≤ k) ∧
      ∃ o, outcomesP {} counterMaskModel (env behaved) (lockRoot (.sem k) (bus.map BUse.toUse) as) o ∧
        o.summary = .done (.succeeded (.pair (.nat (k + released as)) (.int 2))) ∧
        OkJoined bus as 0 ∧ OkJoined bus as 2 ∧
        joinRecV 0 (.ocSucceeded .unit) ∈ o.out ∧ joinRecV 2 (.ocSucceeded .unit) ∈ o.out := by
  obtain ⟨o, ho, hp⟩ := exists_of_map run2_ok
  simp only [Bool.and_eq_true, beq_iff_eq, List.contains_iff_mem] at hp
  refine ⟨1, bus2, as2, ?_, by decide, o, ⟨3000, [], ho⟩, by simpa [released, as2] using hp.1.1,
    ⟨_, rfl, rfl, by decide, by decide⟩, ⟨_, rfl, rfl, by decide, by decide⟩, hp.1.2, hp.2⟩
  intro i hi
  simp only [bus2, List.length_cons, List.length_nil] at hi
  match i, hi with
  | 0, _ => exact .inr (by decide)
  | 1, _ => exact .inl (by decide)
  | 2, _ => exact .inr (by decide)

/-! ## Statement 2: regressions of review batch 11b

H1: a fatal error in a critical section stops the whole run with `Summary.fatal` (as `IOFiber`
`onFatalFailure` does). The first form of statement 2 ("every stopped run ends `Succeeded`") was
false on this input for every implementation; the current form ("`Succeeded …` or `fatal`",
review batch 12) holds on it through its `fatal` part.

W1: the wrong function "`acquireN(n)` always raises for `n ≥ 2`" satisfied every first-form
`Semaphore` statement. On `Semaphore(2)` with one joined `acqRel 2`, it records `Errored` for the
join, which the new form of statement 2 rejects; v3.7.1 records `Succeeded`. -/

def fatalErr : Err := { code := 0, kind := .fatal }
def busF : List BUse := [.permit 0 (.err fatalErr)]
def asF : List Act := [.join 0]

def fatalRun : Option Obs :=
  runObsP {} counterMaskModel (env behaved) 3000 [] (lockRoot (.sem 1) (busF.map BUse.toUse) asF)

theorem fatalRun_ok : fatalRun.map Obs.summary = some (.fatal fatalErr) := by
  decide +kernel

/-- The fatal input meets the hypotheses of statement 2, and a run of it ends `fatal`: it refutes the
first form, and it meets the `fatal` part of the current form (so it is not `blocked`). -/
theorem fatal_regression :
    AllEnded busF.length asF ∧ (∀ b ∈ busF, b.need ≤ 1) ∧
    ∃ o, outcomesP {} counterMaskModel (env behaved) (lockRoot (.sem 1) (busF.map BUse.toUse) asF) o ∧
      (¬ ∃ v, o.summary = .done (.succeeded v)) ∧ (∃ e, o.summary = .fatal e) ∧ o.summary ≠ .blocked := by
  have h := fatalRun_ok
  cases hr : fatalRun with
  | none => rw [hr] at h; simp at h
  | some o =>
    rw [hr] at h
    simp only [Option.map_some, Option.some.injEq] at h
    refine ⟨?_, by decide, o, ⟨3000, [], hr⟩, ?_, ⟨_, h⟩, ?_⟩
    · intro i hi
      simp only [busF, List.length_cons, List.length_nil] at hi
      match i, hi with
      | 0, _ => exact .inr (by decide)
    · rintro ⟨v, hv⟩; rw [h] at hv; cases hv
    · rw [h]; intro hb; cases hb

/-- W1 wrong function: `acquireN(n)` raises `E9` for `n ≥ 2` (`acqBody` replaced). -/
def acqRaises (e : UserEnv) : UserEnv where
  call := e.call
  callV id a v :=
    match SL.ofId? id with
    | some (.acqBody _ n) => if 2 ≤ n then { out := .prog (.error { code := 9 }) } else e.callV id a v
    | _ => e.callV id a v

def busW : List BUse := [.acqRel 2]
def asW : List Act := [.join 0]

def w1Run : Option Obs :=
  runObsP {} counterMaskModel (acqRaises (env behaved)) 3000 [] (lockRoot (.sem 2) (busW.map BUse.toUse) asW)
def w1Good : Option Obs :=
  runObsP {} counterMaskModel (env behaved) 3000 [] (lockRoot (.sem 2) (busW.map BUse.toUse) asW)

/-- The wrong function ends `Succeeded`, but the join of the `acqRel 2` use recorded `Errored`, and no
`Succeeded` record exists: the conclusion of statement 2 fails on an input that meets its
hypotheses (`OkJoined busW asW 0`). v3.7.1 records `Succeeded`. -/
theorem w1_breaks :
    w1Run.map (fun o => o.summary == .done (.succeeded (.pair (.nat 2) (.int 2))) &&
      o.out.contains (joinRecV 0 (.ocErrored { code := 9 })) &&
      !(o.out.any fun x => match x with | .pair (.nat 62) (.pair (.nat 0) (.ocSucceeded _)) => true | _ => false)) = some true ∧
    w1Good.map (fun o => o.summary == .done (.succeeded (.pair (.nat 2) (.int 2))) &&
      o.out.contains (joinRecV 0 (.ocSucceeded .unit))) = some true := by
  constructor <;> decide +kernel

theorem okJoinedW : OkJoined busW asW 0 := ⟨_, rfl, rfl, by decide, by decide⟩

/-! ## Statements 3 and 4: two counted uses, one at a time -/

def us3 : List Use := [.counted 2, .counted 2]
def as3 : List Act := [.join 0, .join 1]

def run3 : Option Obs := runObsP {} counterMaskModel (env cu) 3000 [] (lockRoot (.sem 1) us3 as3)
def run4 : Option Obs := runObsP {} counterMaskModel (env cu) 3000 [] (lockRoot .mutex us3 as3)

theorem run3_ok : run3.map (fun o => highest o == some 1 && o.summary == .done (.succeeded (.pair (.nat 1) (.int 1)))) = some true := by
  decide +kernel

theorem run4_ok : run4.map (fun o => highest o == some 1 && o.summary == .done (.succeeded .unit)) = some true := by
  decide +kernel

theorem noRelease3 : ∀ a ∈ as3, ∀ n, a ≠ .release n := by
  intro a ha n h
  simp only [as3, List.mem_cons, List.not_mem_nil, or_false] at ha
  rcases ha with rfl | rfl <;> cases h

theorem semAtMostK_satisfiable :
    ∃ (u : UserEnv) (k : Nat) (us : List Use) (as : List Act),
      (∀ a ∈ as, ∀ n, a ≠ .release n) ∧ WellFormed semLib [] (env u) (lockRoot (.sem k) us as) ∧
      ∃ o, outcomesP {} counterMaskModel (env u) (lockRoot (.sem k) us as) o ∧ highest o = some k ∧
        2 ≤ us.length := by
  obtain ⟨o, ho, hp⟩ := exists_of_map run3_ok
  refine ⟨cu, 1, us3, as3, noRelease3, wfConst _ (by decide +kernel), o, ⟨3000, [], ho⟩, ?_, by decide⟩
  simp only [Bool.and_eq_true, beq_iff_eq] at hp
  exact hp.1

theorem mutexMutualExclusion_satisfiable :
    ∃ (u : UserEnv) (us : List Use) (as : List Act),
      WellFormed semLib [] (env u) (lockRoot .mutex us as) ∧
      ∃ o, outcomesP {} counterMaskModel (env u) (lockRoot .mutex us as) o ∧ highest o = some 1 ∧
        2 ≤ us.length := by
  obtain ⟨o, ho, hp⟩ := exists_of_map run4_ok
  refine ⟨cu, us3, as3, wfConst _ (by decide +kernel), o, ⟨3000, [], ho⟩, ?_, by decide⟩
  simp only [Bool.and_eq_true, beq_iff_eq] at hp
  exact hp.1

/-! ## Statement 5 -/

def bus5 : List BUse := [.permit 1 (.ok .unit), .permit 0 .canc]
def as5 : List Act := [.join 0, .join 1]

def run5 : Option Obs :=
  runObsP {} counterMaskModel (env behaved) 3000 [] (lockRoot .mutex (bus5.map BUse.toUse) as5)

theorem run5_ok : run5.map (fun o => o.summary == .done (.succeeded .unit) &&
    o.out.contains (joinRecV 0 (.ocSucceeded .unit))) = some true := by
  decide +kernel

theorem mutexNoDeadlock_satisfiable :
    ∃ (bus : List BUse) (as : List Act),
      AllEnded bus.length as ∧ (∀ b ∈ bus, ∃ k bb, b = .permit k bb) ∧
      ∃ o, outcomesP {} counterMaskModel (env behaved) (lockRoot .mutex (bus.map BUse.toUse) as) o ∧
        o.summary = .done (.succeeded .unit) ∧ OkJoined bus as 0 ∧
        joinRecV 0 (.ocSucceeded .unit) ∈ o.out := by
  obtain ⟨o, ho, hp⟩ := exists_of_map run5_ok
  simp only [Bool.and_eq_true, beq_iff_eq, List.contains_iff_mem] at hp
  refine ⟨bus5, as5, ?_, ?_, o, ⟨3000, [], ho⟩, hp.1, ⟨_, rfl, rfl, by decide, by decide⟩, hp.2⟩
  · intro i hi
    simp only [bus5, List.length_cons, List.length_nil] at hi
    match i, hi with
    | 0, _ => exact .inr (by decide)
    | 1, _ => exact .inr (by decide)
  · intro b hb
    simp only [bus5, List.mem_cons, List.not_mem_nil, or_false] at hb
    rcases hb with h | h <;> exact ⟨_, _, h⟩

/-! ## Statement 7 -/

def run7 : Option Obs := runObsP {} counterMaskModel fifoEnv 3000 [] (fifoRoot [2, 1] 2)

theorem run7_ok : run7.map (fun o => o.summary == .done (.succeeded (.int (-1)))) = some true := by
  decide +kernel

theorem semFifo_satisfiable :
    ∃ (ns : List Nat) (r : Nat) (o : Obs), outcomesP {} counterMaskModel fifoEnv (fifoRoot ns r) o ∧
      o.summary = .done (.succeeded (.int ((r : Int) - (ns.foldl (· + ·) 0 : Nat)))) ∧ r < ns.foldl (· + ·) 0 := by
  obtain ⟨o, ho, hp⟩ := exists_of_map run7_ok
  exact ⟨[2, 1], 2, o, ⟨3000, [], ho⟩, by simpa using hp, by decide⟩

/-! ## Statement 8 -/

def run8m : Option Obs := runObsP {} counterMaskModel (env cu) 3000 [] (lockRoot .mutex us3 as3)
def run8s : Option Obs := runObsP {} counterMaskModel (env cu) 3000 [] (lockRoot .semMutex us3 as3)

theorem run8_ok : (run8m.map core == run8s.map core && run8m.map Obs.summary == some (.done (.succeeded .unit))) = true := by
  decide +kernel

theorem mutexSemaphoreTwin_satisfiable :
    ∃ (u : UserEnv) (gs : List Use) (as : List Act),
      (∀ x ∈ gs, ∃ g, x = .permit g ∨ x = .counted g) ∧ (∀ a ∈ as, ∀ n, a ≠ .release n) ∧
      WellFormed semLib [] (env u) (lockRoot .mutex gs as) ∧
      WellFormed semLib [] (env u) (lockRoot .semMutex gs as) ∧
      ∃ o o', outcomesP {} counterMaskModel (env u) (lockRoot .mutex gs as) o ∧
        outcomesP {} counterMaskModel (env u) (lockRoot .semMutex gs as) o' ∧ core o' = core o := by
  have h := run8_ok
  cases hm : run8m with
  | none => rw [hm] at h; simp at h
  | some o =>
    cases hs : run8s with
    | none => rw [hm, hs] at h; simp at h
    | some o' =>
      rw [hm, hs] at h
      simp only [Option.map_some, Bool.and_eq_true, beq_iff_eq, Option.some.injEq] at h
      refine ⟨cu, us3, as3, ?_, noRelease3, wfConst _ (by decide +kernel), wfConst _ (by decide +kernel),
        o, o', ⟨3000, [], hm⟩, ⟨3000, [], hs⟩, h.1.symm⟩
      intro x hx
      simp only [us3, List.mem_cons, List.not_mem_nil, or_false] at hx
      rcases hx with h | h <;> exact ⟨2, .inr h⟩

/-! ## Statements 9 and 10 (sequential specifications; review batch 14) -/

def ops9 : List SOp := [.tryAcq 1, .tryAcq 1, .avail, .count, .rel 1, .permit, .acq 1, .acq 1]

theorem run9_ok : (runObsP {} counterMaskModel seqEnv 3000 [] (semSeqRoot 1 ops9)).map
    (fun o => o.out.reverse == (semSpec 1 ops9).1 && o.summary == .blocked) = some true := by
  decide +kernel

/-- The interesting case: `tryAcquireN` answers both `true` and `false`, and the script blocks at
the last `acquireN` (the spec says so: no permit is left). -/
theorem semSeqSpec_satisfiable :
    ∃ (k : Nat) (ops : List SOp), (∀ op ∈ ops, op ≠ .lock ∧ op ≠ .lockNested) ∧
      (semSpec k ops).1.take 2 = [.pair (.nat 3) (.bool true), .pair (.nat 3) (.bool false)] ∧
      (semSpec k ops).2 = true ∧
      ∃ o, outcomesP {} counterMaskModel seqEnv (semSeqRoot k ops) o ∧
        o.out.reverse = (semSpec k ops).1 ∧ o.summary = .blocked := by
  have h := run9_ok
  cases hr : runObsP {} counterMaskModel seqEnv 3000 [] (semSeqRoot 1 ops9) with
  | none => rw [hr] at h; simp at h
  | some o =>
    rw [hr] at h
    simp only [Option.map_some, Option.some.injEq, Bool.and_eq_true, beq_iff_eq] at h
    refine ⟨1, ops9, ?_, by decide, by decide, o, ⟨3000, [], hr⟩, h.1, h.2⟩
    intro op hop
    simp only [ops9, List.mem_cons, List.not_mem_nil, or_false] at hop
    rcases hop with h | h | h | h | h | h | h | h <;> subst h <;> decide

def ops10 : List SOp := [.lock, .lock, .lockNested]

theorem run10_ok : (runObsP {} counterMaskModel seqEnv 3000 [] (mutexSeqRoot ops10)).map
    (fun o => o.out.reverse == (mutexSpec ops10).1 && o.summary == .blocked) = some true := by
  decide +kernel

/-- The interesting case: two `lock.use` succeed, the nested one deadlocks. -/
theorem mutexSeqSpec_satisfiable :
    ∃ ops : List SOp, (∀ op ∈ ops, op = .lock ∨ op = .lockNested) ∧ (mutexSpec ops).1.length = 2 ∧
      ∃ o, outcomesP {} counterMaskModel seqEnv (mutexSeqRoot ops) o ∧
        o.out.reverse = (mutexSpec ops).1 ∧ o.summary = .blocked := by
  have h := run10_ok
  cases hr : runObsP {} counterMaskModel seqEnv 3000 [] (mutexSeqRoot ops10) with
  | none => rw [hr] at h; simp at h
  | some o =>
    rw [hr] at h
    simp only [Option.map_some, Option.some.injEq, Bool.and_eq_true, beq_iff_eq] at h
    refine ⟨ops10, ?_, by decide, o, ⟨3000, [], hr⟩, h.1, h.2⟩
    intro op hop
    simp only [ops10, List.mem_cons, List.not_mem_nil, or_false] at hop
    rcases hop with h | h | h <;> subst h <;> simp

end CatsEffectInLean.Proofs.Phase7.SemaphoreWitness
