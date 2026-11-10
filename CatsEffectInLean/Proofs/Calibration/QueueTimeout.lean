import CatsEffectInLean.Props.Calibration.QueueTimeout

/-!
# Refutation of `takeTimeoutNoLostElement` (CE-0003)

Counterexample: program A of `reproducers/CE-0003/Repro.scala` with the reproducer values:
one element `42`, timeout `1000` (1 second in ms), sleep `1` (1 ms).

Schedule: the empty choice list, so the replay scheduler always runs ready task 0 (FIFO).
Tasks (fiber ids: `f0` root, `f1` consumer, `f2` = `take` racer, `f3` = `sleep` racer,
`f4`/`f5` = the cancel fibers of the `racePair` finalizer):

1. `f0`: `Queue.unbounded`, `start` the consumer, `IO.sleep(1)` suspends (timer `t0`).
2. `f1`: `timeoutTo` enters `poll(racePair(take, sleep 1000))`; `RacePair` starts `f2`, `f3`;
   `f1` suspends in `Get` (cancelable: inside `poll`).
3. `f2`: `take` finds the buffer empty, registers as a taker and suspends in `wait`.
4. `f3`: `IO.sleep(1000)` suspends (timer `t1`).
5. Time moves to 1: `t0` resumes `f0`.
6. `f0`: `offer(42)` puts `42` in the buffer, and `notifyOne` resumes `f2`. Then
   `consumer.cancel`: `f1` is suspended, so the canceller takes it over and schedules it
   (`IOFiber.scala:155-161`); `f0` waits.
7. `f2`: `poll(take)` takes `42` from the buffer; `f2` completes `Succeeded(42)`; its race
   callback calls the `ContState` of `f1`, but `f1` is canceled: the callback loses
   (`IOFiber.scala:711-715`), and the outcome `Succeeded(42)` is dropped.
8. `f1`: runs its finalizers: the `racePair` finalizer cancels `f2` (already done) and `f3`
   (`IOFiber.scala:940-946`, fibers `f4`, `f5`). `f1` completes `Canceled`.
9. `f0`: `consumer.join` gives `Canceled`; `tryTake` gives `None`.

The root completes `Succeeded(())`. The trace has `Canceled` and `None`: `42` is not returned
and not in the queue. Upstream seeds of the reproducer show the same loss (328 of 500 seeds in
program A under `TestControl`).

A schedule that runs `f1` and then `f4` before `f2` (choices `pick 0` ×6, `pick 1`, `pick 1`)
gives `Canceled` and `Some(42)`: the model does not lose the element on every schedule.

The witness is well-formed (`cx_wellFormed`, decision 27): the start program passes `progOK`
(`decide +kernel`), and each program closure (`PLam`, user code) passes `CallOK` for every
argument and heap view (`call_ok`): it uses `q` and `consumer` only after it received them,
and it reads only the outcome of `consumer`.

Wrong-function test (argument, not run): if the `racePair` finalizer handed a completed child
outcome to the caller (the upstream "lossless cancelation" idea, draft PR #4710), `join` would
give `Succeeded(42)` on this schedule, `returned` would be `[42]`, and `cx_not_perm` would
fail. The schedule with `pick 1, pick 1` above shows that the statement can tell a lossless
run from a lossy one.
-/

namespace CatsEffectInLean.Proofs.Calibration.QueueTimeout

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Props.Calibration.QueueTimeout

/-- The observation of the counterexample run. -/
def cxObs : Obs where
  summary := .done (.succeeded .unit)
  out := [.none, .ocCanceled]
  refs := [.none, .pair (.nat 1) .none, .none]
  reports := []

/-- The FIFO run of program A (`[42]`, timeout `1000`, sleep `1`) for 200 micro-steps ends
with `cxObs`. -/
theorem cx_run : runObs {} counterMaskModel env 200 [] (progA [42] 1000 1) = some cxObs := by
  decide +kernel

/-- `cxObs` is in the outcome set of program A. -/
theorem cx_outcome : outcomes {} counterMaskModel env (progA [42] 1000 1) cxObs :=
  ⟨200, [], by simp, cx_run⟩

/-- Nothing came back: the consumer got `Canceled` and the drain got `None`. -/
theorem cx_not_perm : ¬ (returned cxObs.out).Perm [42] := by
  intro h
  have := h.length_eq
  simp [returned, cxObs] at this

/-! ## The witness is well-formed -/

theorem natsV_handles (xs : List Nat) : (natsV xs).handles = [] := by
  induction xs with
  | nil => rfl
  | cons x xs ih => simpa [natsV, listV, Val.handles] using ih

theorem natsV_of_ofNatsV : ∀ {x : Val} {l : List Nat}, ofNatsV x = some l → natsV l = x
  | .unit, l, h => by simp [ofNatsV] at h; subst h; rfl
  | .pair (.nat n) r, l, h => by
    simp only [ofNatsV, Option.map_eq_some_iff] at h
    obtain ⟨l', hl', rfl⟩ := h
    have := natsV_of_ofNatsV hl'
    simp [natsV, listV] at this ⊢
    exact this
  | .pair (.unit) _, _, h | .pair (.bool _) _, _, h | .pair (.int _) _, _, h
  | .pair (.pair _ _) _, _, h | .pair (.left _) _, _, h | .pair (.right _) _, _, h
  | .pair .none _, _, h | .pair (.some _) _, _, h | .pair (.err _) _, _, h
  | .pair (.ocSucceeded _) _, _, h | .pair (.ocErrored _) _, _, h | .pair .ocCanceled _, _, h
  | .pair (.fiber _) _, _, h | .pair (.ref _) _, _, h | .pair (.deferred _) _, _, h
  | .pair (.poll _ _) _, _, h | .pair (.cont _) _, _, h | .pair (.ec _) _, _, h
  | .pair .trace _, _, h | .pair .runtime _, _, h
  | .bool _, _, h | .nat _, _, h | .int _, _, h | .left _, _, h | .right _, _, h
  | .none, _, h | .some _, _, h | .err _, _, h | .ocSucceeded _, _, h | .ocErrored _, _, h
  | .ocCanceled, _, h | .fiber _, _, h | .ref _, _, h | .deferred _, _, h | .poll _ _, _, h
  | .cont _, _, h | .ec _, _, h | .trace, _, h | .runtime, _, h => by simp [ofNatsV] at h

/-- Decoding the fields of a program closure gives back its closure value. -/
theorem plam_ofFields_inv {tag : Nat} {fs : List Val} {p : PLam}
    (h : PLam.ofFields tag fs = some p) : cloVal ns tag fs = p.toVal := by
  unfold PLam.ofFields at h
  split at h
  all_goals first
    | (cases h; rfl)
    | (cases h; done)
    | (simp only [Option.map_eq_some_iff] at h
       obtain ⟨l, hl, rfl⟩ := h
       simp [PLam.toVal, natsV_of_ofNatsV hl])

theorem isLib_qlam (l : Std.Queue.QLam) : isLib (2 * valToNat l.toVal + 1) = true := by
  have hc := WF.cloOfId_libFn l.toVal
  cases l <;> simp_all [isLib, isLibId, Std.Queue.QLam.toVal, ofCloVal_cloVal,
    Std.Queue.QLam.ofFields, Std.Queue.ns, Timeout.ns] <;> omega

theorem isLib_tlam (l : Timeout.TLam) : isLib (2 * valToNat l.toVal + 1) = true := by
  have hc := WF.cloOfId_libFn l.toVal
  cases l <;> simp_all [isLib, isLibId, Timeout.TLam.toVal, ofCloVal_cloVal,
    Timeout.TLam.ofFields, Std.Queue.ns, Timeout.ns] <;> omega

theorem fnOK_qlam (mem : Handle → Bool) (l : Std.Queue.QLam) :
    WF.fnOK isLib mem l.fn = WF.sub mem l.toVal.handles := by
  simp [Std.Queue.QLam.fn, WF.fnOK_libFn, isLib_qlam]

theorem fnOK_tlam (mem : Handle → Bool) (l : Timeout.TLam) :
    WF.fnOK isLib mem l.fn = WF.sub mem l.toVal.handles := by
  simp [Timeout.TLam.fn, WF.fnOK_libFn, isLib_tlam]

theorem fnOK_rt (lib : Nat → Bool) (mem : Handle → Bool) (k : RtFn) :
    WF.fnOK lib mem (.rt k) = WF.rtOK mem k := rfl

/-- The handles that a call of program closure `p` on `arg` in view `v` holds. -/
abbrev RP (p : PLam) (arg : Val) (v : View) : Handle → Prop :=
  WF.Reach v ([] ++ arg.handles ++ p.toVal.handles)

theorem progOK_drain (R : Handle → Prop) (q : Nat) (hq : R (.ref q)) :
    ∀ n, WF.progOK isLib (WF.memOf R) (drain q n) = true
  | 0 => rfl
  | n + 1 => by
    simp [drain, WF.progOK, Std.Queue.tryTakeIO, fnOK_qlam, PLam.fn, WF.fnOK_userFn, WF.sub,
      Std.Queue.QLam.toVal, PLam.toVal, cloVal, listV, Val.handles, hq]

/-- Each program closure passes `CallOK` (with its closure value as the captured handles). -/
theorem call_ok (p : PLam) (arg : Val) (v : View) :
    (∀ w, WF.Agree (RP p arg v) v w → call p arg w = call p arg v) ∧
    WF.ResultOK isLib (RP p arg v) v (call p arg v) := by
  have hb : ∀ h, h ∈ arg.handles ∨ h ∈ p.toVal.handles → RP p arg v h :=
    fun h hh => WF.Reach.base (by simpa using hh)
  cases p with
  | afterQueue xs d s =>
    refine ⟨fun w _ => rfl, ?_⟩
    cases arg <;> simp [call, prog, illTyped, WF.ResultOK, WF.EffectsOK, WF.OutOK, WF.progOK,
      fnOK_tlam, WF.fnOK_userFn, WF.sub, Timeout.timeoutIO, PLam.fn,
      Timeout.TLam.toVal, PLam.toVal, cloVal, listV, Val.handles, natsV_handles]
    refine hb _ ?_
    simp [Val.handles]
  | afterStart q xs s =>
    refine ⟨fun w _ => rfl, ?_⟩
    cases arg <;> simp [call, prog, illTyped, WF.ResultOK, WF.EffectsOK, WF.OutOK, WF.progOK,
      WF.fnOK_userFn, WF.sub, PLam.fn, PLam.toVal, cloVal, listV, Val.handles, natsV_handles]
    refine ⟨hb _ ?_, hb _ ?_⟩ <;> simp [PLam.toVal, cloVal, listV, Val.handles, natsV_handles]
  | offerNext q c n xs =>
    have hq : RP (.offerNext q c n xs) arg v (.ref q) :=
      hb _ (by simp [PLam.toVal, cloVal, listV, Val.handles, natsV_handles])
    have hc : RP (.offerNext q c n xs) arg v (.fiber c) :=
      hb _ (by simp [PLam.toVal, cloVal, listV, Val.handles, natsV_handles])
    refine ⟨fun w hw => ?_, ?_⟩
    · cases xs with
      | cons x rest => rfl
      | nil => simp [call, hw.2.2.2.2 c hc]
    · cases xs with
      | cons x rest =>
        simp [call, prog, WF.ResultOK, WF.EffectsOK, WF.OutOK, WF.progOK, WF.fnOK_userFn,
          fnOK_qlam, WF.sub, PLam.fn, PLam.toVal, Std.Queue.offerIO,
          Std.Queue.QLam.toVal, cloVal, listV, Val.handles, natsV_handles, hq, hc]
      | nil =>
        cases ho : v.outcome c <;>
          simp [call, prog, ho, IO.cancelOf, WF.ResultOK, WF.EffectsOK, WF.OutOK, WF.progOK,
            WF.fnOK_userFn, fnOK_rt, WF.rtOK, WF.sub, PLam.fn, PLam.toVal, cloVal, listV,
            Val.handles, hq, hc]
  | afterCancel q c n =>
    have hq : RP (.afterCancel q c n) arg v (.ref q) :=
      hb _ (by simp [PLam.toVal, cloVal, listV, Val.handles])
    have hc : RP (.afterCancel q c n) arg v (.fiber c) :=
      hb _ (by simp [PLam.toVal, cloVal, listV, Val.handles])
    refine ⟨fun w hw => by simp [call, hw.2.2.2.2 c hc], ?_⟩
    cases ho : v.outcome c with
    | none =>
      simp [call, prog, ho, IO.joinOf, WF.ResultOK, WF.EffectsOK, WF.OutOK, WF.progOK,
        WF.fnOK_userFn, fnOK_rt, WF.rtOK, WF.sub, PLam.fn, PLam.toVal, cloVal, listV,
        Val.handles, hq, hc]
    | some oc =>
      simp [call, prog, ho, IO.joinOf, WF.ResultOK, WF.EffectsOK, WF.OutOK, WF.progOK,
        WF.fnOK_userFn, WF.sub, PLam.fn, PLam.toVal, cloVal, listV, Val.handles, hq]
      exact fun h hh => WF.Reach.fiber hc ho hh
  | afterJoin q n =>
    have hq : RP (.afterJoin q n) arg v (.ref q) :=
      hb _ (by simp [PLam.toVal, cloVal, listV, Val.handles])
    refine ⟨fun w _ => rfl, ?_⟩
    simp only [call, prog, WF.ResultOK, WF.EffectsOK, WF.OutOK]
    exact ⟨fun h hh => hb h (Or.inl hh), progOK_drain _ q hq n⟩
  | afterTryTake q k =>
    have hq : RP (.afterTryTake q k) arg v (.ref q) :=
      hb _ (by simp [PLam.toVal, cloVal, listV, Val.handles])
    refine ⟨fun w _ => rfl, ?_⟩
    simp only [call, prog, WF.ResultOK, WF.EffectsOK, WF.OutOK]
    exact ⟨fun h hh => hb h (Or.inl hh), progOK_drain _ q hq k⟩

/-- Each user function (even id) of `env` passes `CallOK`. -/
theorem env_calls (id : Nat) (hid : id % 2 = 0) (arg : Val) (v : View) :
    WF.CallOK isLib [] env id arg v := by
  have hlib : isLibId id = false := by simp [isLibId]; omega
  have hE : ∀ w, env.callV id arg w = Props.Calibration.QueueTimeout.dispatch id arg w :=
    fun _ => rfl
  have bad : ∀ (R : Handle → Prop),
      (∀ w, Props.Calibration.QueueTimeout.dispatch id arg w = illTyped) →
      (∀ w, WF.Agree R v w → Props.Calibration.QueueTimeout.dispatch id arg w =
        Props.Calibration.QueueTimeout.dispatch id arg v) ∧
      WF.ResultOK isLib R v (Props.Calibration.QueueTimeout.dispatch id arg v) := by
    intro R hd
    refine ⟨fun w _ => by rw [hd w, hd v], ?_⟩
    simp [hd, illTyped, WF.ResultOK, WF.EffectsOK, WF.OutOK]
  simp only [WF.CallOK, hE]
  cases hc : cloOfId id with
  | none => exact bad _ (fun w => by simp [Props.Calibration.QueueTimeout.dispatch, hc])
  | some c =>
    have hcap : WF.captured id = c.handles := by simp [WF.captured, hc]
    rw [hcap]
    cases ho : ofCloVal c with
    | none => exact bad _ (fun w => by simp [Props.Calibration.QueueTimeout.dispatch, hc, ho])
    | some t =>
      obtain ⟨k, tag, fs⟩ := t
      by_cases hk : k = ns
      · subst hk
        cases hp : PLam.ofFields tag fs with
        | none => exact bad _ (fun w => by simp [Props.Calibration.QueueTimeout.dispatch, hc, ho, hlib, hp])
        | some p =>
          have hcv : c = p.toVal := (cloVal_of_ofCloVal ho).trans (plam_ofFields_inv hp)
          have hd : ∀ w, Props.Calibration.QueueTimeout.dispatch id arg w = call p arg w := by
            intro w; simp [Props.Calibration.QueueTimeout.dispatch, hc, ho, hlib, hp]
          rw [hcv]
          simp only [hd]
          exact call_ok p arg v
      · exact bad _ (fun w => by simp [Props.Calibration.QueueTimeout.dispatch, hc, ho, hlib, hk])

/-- The witness program (one element `42`, timeout `1000`, sleep `1`) is well-formed. -/
theorem cx_wellFormed : WellFormed isLib [] env (progA [42] 1000 1) :=
  ⟨by decide +kernel, fun id hid arg v => env_calls id hid arg v⟩

/-- CE-0003: `Queue.take.timeout` in a canceled fiber loses an element. -/
theorem takeTimeoutNoLostElement_refuted : ¬ takeTimeoutNoLostElement := by
  intro h
  exact cx_not_perm (h [42] 1000 1 cxObs cx_wellFormed cx_outcome .unit rfl)

end CatsEffectInLean.Proofs.Calibration.QueueTimeout
