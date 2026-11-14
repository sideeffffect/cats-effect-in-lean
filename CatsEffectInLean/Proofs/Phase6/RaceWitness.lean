import CatsEffectInLean.Props.Phase6.Race

/-!
# Satisfiability witnesses for the track R statements (decision 53)

For each of `combNoLeak`, `combCanceledNoLeak`, `timeoutNoLeak` and
`raceOutcomeIsWinnerOutcome` (`Props/Phase6/Race.lean`): one concrete input that meets all
hypotheses together (`WellFormed` of the sides, with the statement's own `env`), and one schedule
where the root completes and the interesting case happens. These are not registered properties;
they show that the hypotheses are not vacuous.

User code `u0`: every user call throws. The parent closures (`PLam`, even ids) are the only user
code that runs. `env_calls` and `env_opaque` prove the user-code clauses of `WellFormed` for
every pair of sides (they do not depend on the sides).

| Statement | Input | Schedule | Interesting case |
|---|---|---|---|
| `combNoLeak` | `race(pure 1, never)` | FIFO | both sides start; fiber 1 `Succeeded(1)`; the loser (fiber 2) is `Canceled` |
| `combCanceledNoLeak` | `race(never, never)` in fiber 1 | `pick 0` ×3, `preempt` | the parent's cancel lands while the race runs: both race children (fibers 2, 3) end `Canceled` |
| `timeoutNoLeak` | `never.timeout(1)` | FIFO; parent form `pick 0` ×3, `preempt` | the timer wins: root `Errored(TimeoutException)`, source `Canceled`; parent form: source and sleep (fibers 2, 3) `Canceled` |
| `raceOutcomeIsWinnerOutcome` | `raceOutcome(pure 1, never)` | FIFO | root `Succeeded(Left(Succeeded(1)))`, fiber 1 ended `Succeeded(1)` |

Decision 54 (forged markers): the statements read only the fiber table (`liveRaceChildren`,
`fiberOutcome`) and the root summary, no user-emitted marker. A race child is a fiber with a
`raceLeft`/`raceRight` callback on a `ContState` of the racing fiber; only a `RacePair` run by
that fiber makes one. User code runs in other fibers (the sides) or as a closure called by the
racing fiber's own mirror code; it cannot install a callback, and it cannot name a `ContState`,
`poll` or fiber it does not hold (`progOK`, `CallOK`). A side may contain the race closures or
`PLam` closures itself, but only with handles it holds; that is the public API (a nested race,
`cancel`/`join` of its own fiber).
-/

namespace CatsEffectInLean.Proofs.Phase6.RaceWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Props.Phase6.Race

/-- User code that always throws. -/
def u0 : UserEnv := { call := fun _ _ _ => { out := .throw { code := 999999, kind := .fatal } } }

/-! ## `WellFormed`: the user-code clauses -/

theorem plam_ofFields_inv {tag : Nat} {fs : List Val} {p : PLam}
    (h : PLam.ofFields tag fs = some p) : cloVal ns tag fs = p.toVal := by
  unfold PLam.ofFields at h
  split at h <;> first | (cases h; rfl) | cases h

/-- On an even id, `dispatch` runs a parent closure or `u0`. -/
theorem dispatch_even (fa fb : IO) (id : Nat) (hid : id % 2 = 0) (arg : Val) (v : View) :
    Props.Phase6.Race.dispatch fa fb u0 id arg v =
      match parentOf? id with
      | some p => p.call arg v
      | none => { out := .throw { code := 999999, kind := .fatal } } := by
  have hlib : isLibId id = false := by simp [isLibId]; omega
  simp [Props.Phase6.Race.dispatch, Race.ofId?, timeoutOf?, hlib]
  cases parentOf? id <;> rfl

theorem fnOK_rt (lib : Nat → Bool) (mem : Handle → Bool) (k : RtFn) :
    WF.fnOK lib mem (.rt k) = WF.rtOK mem k := rfl

/-- The handles that a call of parent closure `p` on `arg` in view `v` holds. -/
abbrev RP (p : PLam) (arg : Val) (v : View) : Handle → Prop :=
  WF.Reach v ([] ++ arg.handles ++ p.toVal.handles)

theorem call_ok (p : PLam) (arg : Val) (v : View) :
    (∀ w, WF.Agree (RP p arg v) v w → p.call arg w = p.call arg v) ∧
    WF.ResultOK isLib (RP p arg v) v (p.call arg v) := by
  have hb : ∀ h, h ∈ arg.handles ∨ h ∈ p.toVal.handles → RP p arg v h :=
    fun h hh => WF.Reach.base (by simpa using hh)
  cases p with
  | afterStart =>
    cases arg with
    | fiber f =>
      have hf : RP .afterStart (.fiber f) v (.fiber f) := hb _ (by simp [Val.handles])
      refine ⟨fun w hw => by simp [PLam.call, hw.2.2.2.2 f hf], ?_⟩
      cases ho : v.outcome f <;>
        simp [PLam.call, ho, IO.cancelOf, WF.ResultOK, WF.EffectsOK, WF.OutOK, WF.progOK,
          WF.fnOK_userFn, fnOK_rt, WF.rtOK, WF.sub, PLam.fn, PLam.toVal, cloVal, listV,
          Val.handles, WF.memOf, hf]
    | _ =>
      exact ⟨fun _ _ => rfl, by simp [PLam.call, WF.ResultOK, WF.EffectsOK, WF.OutOK]⟩
  | afterCancel f =>
    have hf : RP (.afterCancel f) arg v (.fiber f) :=
      hb _ (by simp [PLam.toVal, cloVal, listV, Val.handles])
    refine ⟨fun w hw => by simp [PLam.call, hw.2.2.2.2 f hf], ?_⟩
    cases ho : v.outcome f with
    | none =>
      simp [PLam.call, ho, IO.joinOf, WF.ResultOK, WF.EffectsOK, WF.OutOK, WF.progOK,
        WF.fnOK, WF.rtOK, WF.memOf, hf]
    | some oc =>
      simp [PLam.call, ho, IO.joinOf, WF.ResultOK, WF.EffectsOK, WF.OutOK, WF.progOK, WF.sub,
        WF.memOf]
      exact fun h hh => WF.Reach.fiber hf ho hh

/-- Each user function (even id) of `env fa fb u0` passes `CallOK`. -/
theorem env_calls (fa fb : IO) (id : Nat) (hid : id % 2 = 0) (arg : Val) (v : View) :
    WF.CallOK isLib [] (env fa fb u0) id arg v := by
  have hE : ∀ w, (env fa fb u0).callV id arg w = Props.Phase6.Race.dispatch fa fb u0 id arg w := fun _ => rfl
  simp only [WF.CallOK, hE, dispatch_even fa fb id hid]
  cases hp : parentOf? id with
  | none =>
    exact ⟨fun _ _ => rfl, by simp [WF.ResultOK, WF.EffectsOK, WF.OutOK]⟩
  | some p =>
    have hlib : isLibId id = false := by simp [isLibId]; omega
    simp only [parentOf?, hlib, Bool.false_eq_true, ite_false] at hp
    cases hc : cloOfId id with
    | none => simp [hc] at hp
    | some c =>
      cases ho : ofCloVal c with
      | none => simp [hc, ho] at hp
      | some t =>
        obtain ⟨k, tag, fs⟩ := t
        simp only [hc, ho, Option.bind_some] at hp
        by_cases hk : k = ns
        · subst hk
          simp only [beq_self_eq_true, ite_true] at hp
          have hcv : c = p.toVal := (cloVal_of_ofCloVal ho).trans (plam_ofFields_inv hp)
          have hcap : WF.captured id = p.toVal.handles := by simp [WF.captured, hc, hcv]
          rw [hcap]
          exact call_ok p arg v
        · simp [hk] at hp

/-! ### Clause 6: `Poll` values are opaque -/

theorem plam_hasPoll (p : PLam) : WF.hasPoll p.toVal = false := by
  cases p <;> simp [PLam.toVal, cloVal, listV, WF.hasPoll]

theorem rnView_outcome (σ : WF.PollRen) (v : View) (t : Nat) :
    (WF.rnView σ v).outcome t = (v.outcome t).map (WF.rnOutcome σ) := by
  simp only [View.outcome, WF.rnView, List.getElem?_map]
  cases v.outcomes[t]? with
  | none => rfl
  | some o => cases o <;> rfl

theorem rnVal_toVal (σ : WF.PollRen) (oc : Outcome) :
    WF.rnVal σ oc.toVal = (WF.rnOutcome σ oc).toVal := by
  cases oc <;> rfl

theorem call_rn (σ : WF.PollRen) (p : PLam) (arg : Val) (v : View) :
    p.call (WF.rnVal σ arg) (WF.rnView σ v) = WF.rnResult σ (p.call arg v) := by
  cases p with
  | afterStart =>
    cases arg with
    | fiber f =>
      cases ho : v.outcome f <;>
        simp [PLam.call, ho, rnView_outcome, IO.cancelOf, WF.rnResult, WF.rnIO, WF.rnVal,
          PLam.fn, PLam.toVal, cloVal, listV] <;> rfl
    | poll m s => simp [PLam.call, WF.rnVal, WF.rnResult]
    | pair a b => simp [PLam.call, WF.rnVal, WF.rnResult]
    | left a => simp [PLam.call, WF.rnVal, WF.rnResult]
    | right a => simp [PLam.call, WF.rnVal, WF.rnResult]
    | some a => simp [PLam.call, WF.rnVal, WF.rnResult]
    | ocSucceeded a => simp [PLam.call, WF.rnVal, WF.rnResult]
    | _ => simp [PLam.call, WF.rnVal, WF.rnResult]
  | afterCancel f =>
    cases ho : v.outcome f <;>
      simp [PLam.call, ho, rnView_outcome, IO.joinOf, WF.rnResult, WF.rnIO, rnVal_toVal] <;> rfl

/-- An even id whose closure value holds a `Poll` is not a parent closure. -/
theorem parentOf_poll (id : Nat) (c : Val) (hc : cloOfId id = some c) (hp : WF.hasPoll c = true) :
    parentOf? id = none := by
  unfold parentOf?
  split
  · rfl
  · simp only [hc, Option.bind_some]
    cases ho : ofCloVal c with
    | none => rfl
    | some t =>
      obtain ⟨k, tag, fs⟩ := t
      by_cases hk : k = ns
      · subst hk
        cases hpl : PLam.ofFields tag fs with
        | none => simp [hpl]
        | some p =>
          have hcv : c = p.toVal := (cloVal_of_ofCloVal ho).trans (plam_ofFields_inv hpl)
          rw [hcv, plam_hasPoll] at hp
          cases hp
      · simp [hk]

theorem env_opaque (fa fb : IO) : WF.PollOpaque (env fa fb u0) := by
  intro σ _ id hid arg v
  show Props.Phase6.Race.dispatch fa fb u0 (WF.rnId σ id) (WF.rnVal σ arg) (WF.rnView σ v) =
    WF.rnResult σ (Props.Phase6.Race.dispatch fa fb u0 id arg v)
  have hid' : WF.rnId σ id % 2 = 0 := by rw [WF.rnId_mod_two]; exact hid
  rw [dispatch_even fa fb _ hid', dispatch_even fa fb _ hid]
  cases hc : cloOfId id with
  | none =>
    rw [WF.rnId_of_noPoll σ id (by simp [hc])]
    have : parentOf? id = none := by simp [parentOf?, hc]
    simp [this, WF.rnResult]
  | some c =>
    by_cases hp : WF.hasPoll c = true
    · have hc' : cloOfId (WF.rnId σ id) = some (WF.rnVal σ c) := by
        rw [WF.cloOfId_rnId, hc]; rfl
      have hp' : WF.hasPoll (WF.rnVal σ c) = true := by simpa using hp
      rw [parentOf_poll _ _ hc' hp', parentOf_poll _ _ hc hp]
      rfl
    · rw [WF.rnId_of_noPoll σ id (by intro c' h; rw [hc] at h; cases h; simpa using hp)]
      cases hpo : parentOf? id with
      | none => simp [WF.rnResult]
      | some p => exact call_rn σ p arg v

/-- `WellFormed` of a side whose start program passes `progOK`. -/
theorem wf_of_progOK (fa fb p : IO) (h : WF.progOK isLib (([] : List Handle).contains ·) p = true) :
    WellFormed isLib [] (env fa fb u0) p :=
  ⟨h, fun id hid arg v => env_calls fa fb id hid arg v, env_opaque fa fb⟩

/-! ## The witnesses -/

def pure1 : IO := .pure (.nat 1)
def nev : IO := Timeout.neverIO

theorem pure1_wf (fa fb : IO) : WellFormed isLib [] (env fa fb u0) pure1 :=
  wf_of_progOK fa fb pure1 (by decide +kernel)

theorem nev_wf (fa fb : IO) : WellFormed isLib [] (env fa fb u0) nev :=
  wf_of_progOK fa fb nev (by decide +kernel)

/-- The parent's cancel lands while the race runs. -/
def parentSched : List PChoice := [.pick 0, .pick 0, .pick 0, .preempt]

theorem combNoLeak_run :
    let s := run pure1 nev u0 3000 [] (Race.combIO .race src0 src1)
    s.rootDone = true ∧ fiberOutcome s 1 = some (.succeeded (.nat 1)) ∧
      fiberOutcome s 2 = some .canceled := by
  decide +kernel

/-- `combNoLeak`: all hypotheses hold for `race(pure 1, never)`, and on the FIFO schedule the
root completes after both sides ran and the loser was canceled. -/
theorem combNoLeak_witness :
    ∃ (k : Race.Kind) (u : UserEnv) (fa fb : IO),
      WellFormed isLib [] (env fa fb u) fa ∧ WellFormed isLib [] (env fa fb u) fb ∧
      ∃ (fuel : Nat) (cs : List PChoice),
        (run fa fb u fuel cs (Race.combIO k src0 src1)).rootDone = true ∧
        fiberOutcome (run fa fb u fuel cs (Race.combIO k src0 src1)) 2 = some .canceled :=
  ⟨.race, u0, pure1, nev, pure1_wf _ _, nev_wf _ _, 3000, [], combNoLeak_run.1, combNoLeak_run.2.2⟩

theorem combCanceledNoLeak_run :
    let s := run nev nev u0 3000 parentSched (parentIO (Race.combIO .race src0 src1))
    s.rootDone = true ∧ fiberOutcome s 1 = some .canceled ∧
      fiberOutcome s 2 = some .canceled ∧ fiberOutcome s 3 = some .canceled := by
  decide +kernel

/-- `combCanceledNoLeak`: all hypotheses hold for `race(never, never)`; with one preemption the
parent's cancel lands while the race runs, and both race children of fiber 1 end `Canceled`. -/
theorem combCanceledNoLeak_witness :
    ∃ (k : Race.Kind) (u : UserEnv) (fa fb : IO),
      WellFormed isLib [] (env fa fb u) fa ∧ WellFormed isLib [] (env fa fb u) fb ∧
      ∃ (fuel : Nat) (cs : List PChoice),
        let s := run fa fb u fuel cs (parentIO (Race.combIO k src0 src1))
        s.rootDone = true ∧ fiberOutcome s 2 = some .canceled ∧ fiberOutcome s 3 = some .canceled :=
  ⟨.race, u0, nev, nev, nev_wf _ _, nev_wf _ _, 3000, parentSched,
    combCanceledNoLeak_run.1, combCanceledNoLeak_run.2.2⟩

theorem timeout_run :
    let s := run nev nev u0 3000 [] (Timeout.timeoutIO src0 1)
    s.rootDone = true ∧ s.halt = some (.done (.errored Timeout.timeoutErr)) ∧
      fiberOutcome s 1 = some .canceled ∧ fiberOutcome s 2 = some (.succeeded .unit) := by
  decide +kernel

theorem timeout_parent_run :
    let s := run nev nev u0 3000 parentSched (parentIO (Timeout.timeoutIO src0 1))
    s.rootDone = true ∧ fiberOutcome s 2 = some .canceled ∧ fiberOutcome s 3 = some .canceled := by
  decide +kernel

/-- `timeoutNoLeak`: the hypothesis holds for `never.timeout(1)`; directly the timer wins
(`TimeoutException`, source canceled); in the parent form the cancel lands while the timeout's
race runs (source and sleep canceled). -/
theorem timeoutNoLeak_witness :
    ∃ (d : Nat) (u : UserEnv) (fa : IO),
      WellFormed isLib [] (env fa fa u) fa ∧
      (∃ (fuel : Nat) (cs : List PChoice),
        let s := run fa fa u fuel cs (Timeout.timeoutIO src0 d)
        s.halt = some (.done (.errored Timeout.timeoutErr)) ∧ fiberOutcome s 1 = some .canceled) ∧
      (∃ (fuel : Nat) (cs : List PChoice),
        let s := run fa fa u fuel cs (parentIO (Timeout.timeoutIO src0 d))
        s.rootDone = true ∧ fiberOutcome s 2 = some .canceled ∧ fiberOutcome s 3 = some .canceled) :=
  ⟨1, u0, nev, nev_wf _ _, ⟨3000, [], timeout_run.2.1, timeout_run.2.2.1⟩,
    ⟨3000, parentSched, timeout_parent_run⟩⟩

theorem raceOutcome_run :
    let s := run pure1 nev u0 3000 [] (Race.raceOutcomeIO src0 src1)
    s.halt = some (.done (.succeeded (.left (.ocSucceeded (.nat 1))))) ∧
      fiberOutcome s 1 = some (.succeeded (.nat 1)) ∧ fiberOutcome s 2 = some .canceled := by
  decide +kernel

/-- `raceOutcomeIsWinnerOutcome`: the hypotheses hold for `raceOutcome(pure 1, never)`, and the
root completes with `Succeeded(Left(oc))` (the antecedent of the claim) after the loser was
canceled. -/
theorem raceOutcomeIsWinnerOutcome_witness :
    ∃ (u : UserEnv) (fa fb : IO),
      WellFormed isLib [] (env fa fb u) fa ∧ WellFormed isLib [] (env fa fb u) fb ∧
      ∃ (fuel : Nat) (cs : List PChoice) (v : Val),
        (run fa fb u fuel cs (Race.raceOutcomeIO src0 src1)).halt = some (.done (.succeeded v)) ∧
        fiberOutcome (run fa fb u fuel cs (Race.raceOutcomeIO src0 src1)) 2 = some .canceled :=
  ⟨u0, pure1, nev, pure1_wf _ _, nev_wf _ _, 3000, [], _, raceOutcome_run.1, raceOutcome_run.2.2⟩

/-! ## Wrong-function test (kernel-checked)

A `race` whose `Succeeded` branch does not cancel the loser (`fa.map(Left(_))` without
`f.cancel *>`) leaks on `race(pure 1, never)`: the root completes while fiber 2 is a live race
child. So `combNoLeak` is not satisfied by every function. -/

/-- `env pure1 nev u0` with the wrong `race`. -/
def noCancelEnv : UserEnv :=
  let e := env pure1 nev u0
  { call := e.call
    callV := fun id arg v =>
      match Race.ofId? id, arg with
      | some (.sel .race _ _), .left (.pair (.ocSucceeded a) _) =>
        { out := .prog (.map (.pure a) (Race.RLam.inj 0).fn) }
      | some (.sel .race _ _), .right (.pair _ (.ocSucceeded b)) =>
        { out := .prog (.map (.pure b) (Race.RLam.inj 1).fn) }
      | _, _ => e.callV id arg v }

theorem noCancel_leaks :
    let s := runSchedStateP {} counterMaskModel noCancelEnv 3000 []
      (Sched.init counterMaskModel (Race.combIO .race src0 src1))
    s.rootDone = true ∧ liveRaceChildren s 0 = [2] := by
  decide +kernel

end CatsEffectInLean.Proofs.Phase6.RaceWitness
