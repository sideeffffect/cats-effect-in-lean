import CatsEffectInLean.Proofs.Phase6.BracketFullTwin

/-!
# Satisfiability witnesses of the track G statements (decision 53)

Review batch 4 found two statements vacuous (their hypotheses never held together). Decision 53:
each registered statement with non-trivial hypotheses needs one concrete input that meets all
hypotheses together and reaches the interesting case. Kernel-checked here:

* `bracketReleaseOnce_satisfiable`: user code `use = _ => IO.cede`, `rel = _ => IO.unit`,
  acquire `IO.pure(5)`. All hypotheses hold, and one run ends with acquire completed, release
  run once and the child canceled by the parent (`Canceled` in the parent's `join`).
* `guaranteeFinalizerOnce_satisfiable`: `k = _ => IO.cede`, `q = _ => IO.unit`. All hypotheses
  hold, and one run ends with `fa` started, the finalizer run once and the child canceled.
* `bracketFullIsKernelDefaultPureUse_satisfiable`: the CE-0005 environment with a pure `use`
  (`_ => IO.unit`) and acquire `IO.canceled` (a cancel is pending after acquire, the case that
  separates the two bodies when `use` throws). `LibEnv`, `PureFn` and both `WellFormed` hold,
  and the left side has the observation `Canceled`.
* `guaranteeIsGuaranteeCase_satisfiable`: `fa = IO.raiseError(E2)`, `fin = IO.delay(emit 3)`,
  `k = _ => fin`. All hypotheses hold, and the left side runs the finalizer (`out = [3]`) and
  ends `Errored(E2)`.
-/

namespace CatsEffectInLean.Proofs.Phase6.BracketWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.Bracket
open CatsEffectInLean.Props.Phase6.Bracket

/-! ## The invariants: user code `_ => IO.cede` (id 2) and `_ => IO.unit` (id 4) -/

def wR : Nat → UserResult
  | 1 => { out := .prog .cede }
  | 2 => { out := .prog (.pure .unit) }
  | _ => { out := .throw { code := 0 } }

def wu : UserEnv where
  call id _ _ := wR (id / 2)

theorem henv_even (a0 : IO) (id : Nat) (hid : id % 2 = 0) (a : Val) (v : View) :
    (henv a0 wu).callV id a v = wR (id / 2) := by
  have h1 : HLam.ofId? id = none := by simp [HLam.ofId?, Codec.isLibId, hid]
  show hdispatch a0 wu id a v = _
  simp [hdispatch, h1, BLam.ofId?_even hid]; rfl

theorem wR_ok (n : Nat) (R : Handle → Prop) (v : View) : WF.ResultOK isLib R v (wR n) := by
  match n with
  | 0 | 1 | 2 => simp [wR, WF.ResultOK, WF.EffectsOK, WF.OutOK, WF.progOK, WF.sub, Val.handles]
  | _ + 3 => simp [wR, WF.ResultOK, WF.EffectsOK, WF.OutOK]

theorem wf (a0 p : IO) (hp : WF.progOK isLib (fun h => ([] : List Handle).contains h) p = true) :
    WellFormed isLib [] (henv a0 wu) p := by
  refine ⟨hp, fun id hid arg v => ⟨fun w _ => ?_, ?_⟩, ?_⟩
  · rw [henv_even a0 id hid, henv_even a0 id hid]
  · rw [henv_even a0 id hid]; exact wR_ok _ _ _
  · refine WF.pollOpaque_of_const (henv a0 wu) (fun id => wR (id / 2)) [2, 4]
      { out := .throw { code := 0 } } (fun id arg v hid => henv_even a0 id hid arg v)
      (by decide +kernel) ?_ ?_ (fun _ _ => rfl)
    · intro id hid hk
      simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hk
      obtain h | h : id / 2 = 0 ∨ 3 ≤ id / 2 := by omega
      · simp only [h]; rfl
      · obtain ⟨k, hk⟩ := Nat.exists_eq_add_of_le h
        simp only [hk, show 3 + k = k + 3 by omega]; rfl
    · intro σ _ k hk
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hk
      rcases hk with rfl | rfl <;> rfl

/-- A schedule: picks, with three preemptions (found by `exploreP`; its paths are stored newest
first, so these are the reversed paths). -/
def csR : List PChoice :=
  List.replicate 4 (.pick 0) ++ [.preempt] ++ List.replicate 2 (.pick 0) ++ [.preempt] ++
    List.replicate 3 (.pick 0) ++ [.preempt] ++ List.replicate 25 (.pick 0)

def csG : List PChoice :=
  List.replicate 4 (.pick 0) ++ [.preempt] ++ List.replicate 7 (.pick 0) ++ [.preempt] ++
    List.replicate 3 (.pick 0) ++ [.preempt] ++ List.replicate 15 (.pick 0)

/-- The interesting run: child canceled, acquire completed, release run once. -/
def relCase (o : Obs) : Bool :=
  o.summary == .done (.succeeded .ocCanceled) && count o 0 == 1 && count o 1 == 1

theorem relRun : (runObsP {} counterMaskModel (henv (.pure (.nat 5)) wu) 400 csR (harness 0 2 4)).map relCase
    = some true := by decide +kernel

theorem finRun : (runObsP {} counterMaskModel (henv (.pure .unit) wu) 400 csG (harness 1 2 4)).map relCase
    = some true := by decide +kernel

theorem exists_of_map {o? : Option Obs} {p : Obs → Bool} (h : o?.map p = some true) :
    ∃ o, o? = some o ∧ p o = true := by
  cases o? with
  | none => cases h
  | some o => exact ⟨o, rfl, by simpa using h⟩

/-- All hypotheses of `bracketReleaseOnce` hold together, and a run reaches the interesting
case (acquire completed, release run, child canceled by the parent). -/
theorem bracketReleaseOnce_satisfiable :
    ∃ (u : UserEnv) (a0 : IO) (use rel : Nat),
      use % 2 = 0 ∧ rel % 2 = 0 ∧ WellFormed isLib [] (henv a0 u) a0 ∧
      ∃ o, outcomesP {} counterMaskModel (henv a0 u) (harness 0 use rel) o ∧
        o.summary = .done (.succeeded .ocCanceled) ∧ count o 0 = 1 ∧ count o 1 = 1 := by
  obtain ⟨o, ho, hp⟩ := exists_of_map relRun
  simp only [relCase, Bool.and_eq_true, beq_iff_eq] at hp
  exact ⟨wu, .pure (.nat 5), 2, 4, rfl, rfl, wf _ _ (by decide +kernel), o, ⟨400, csR, ho⟩,
    hp.1.1, hp.1.2, hp.2⟩

/-- All hypotheses of `guaranteeFinalizerOnce` hold together, and a run reaches the interesting
case (`fa` started, the finalizer run, child canceled by the parent). -/
theorem guaranteeFinalizerOnce_satisfiable :
    ∃ (u : UserEnv) (k q : Nat),
      k % 2 = 0 ∧ q % 2 = 0 ∧ WellFormed isLib [] (henv (.pure .unit) u) (.pure .unit) ∧
      ∃ o, outcomesP {} counterMaskModel (henv (.pure .unit) u) (harness 1 k q) o ∧
        o.summary = .done (.succeeded .ocCanceled) ∧ count o 0 = 1 ∧ count o 1 = 1 := by
  obtain ⟨o, ho, hp⟩ := exists_of_map finRun
  simp only [relCase, Bool.and_eq_true, beq_iff_eq] at hp
  exact ⟨wu, 2, 4, rfl, rfl, wf _ _ (by decide +kernel), o, ⟨400, csG, ho⟩,
    hp.1.1, hp.1.2, hp.2⟩

/-! ## `bracketFullIsKernelDefaultPureUse` -/

open CatsEffectInLean.Proofs.Phase6.BracketFullWitness in
/-- The CE-0005 environment with the pure `use = _ => IO.unit` (id 4) and acquire `IO.canceled`
(id 0): all hypotheses hold and the left side ends `Canceled` (a cancel is pending after
acquire). -/
theorem bracketFullIsKernelDefaultPureUse_satisfiable :
    ∃ (env : UserEnv) (ioOf : Val → IO) (acq use rel : Nat),
      LibEnv env ioOf ∧ PureFn env use ∧
      WellFormed isLib [] env (bracketFullIO acq use rel) ∧
      WellFormed isLib [] env (defaultBracketFullIO acq use rel) ∧
      outcomesP {} counterMaskModel env (bracketFullIO acq use rel) canceledObs := by
  have hl : outcomesPList {} counterMaskModel env 200 (bracketFullIO 0 4 4) = some [canceledObs] := by
    decide +kernel
  refine ⟨env, ioOf, 0, 4, 4, env_lib, fun a v => ⟨.pure .unit, callV_even 4 rfl a v⟩,
    wellFormed _ (by decide +kernel), wellFormed _ (by decide +kernel), ?_⟩
  exact (outcomesPList_sound {} counterMaskModel env hl canceledObs).mpr (by simp)

/-! ## `guaranteeIsGuaranteeCase` -/

/-- User code: id 2 is the thunk `emit 3`; id 4 is `_ => IO.delay(emit 3)` (`_ => fin`). -/
def gR : Nat → UserResult
  | 1 => { effects := [.emit (.nat 3)], out := .ret .unit }
  | 2 => { out := .prog (.delay (.user 2)) }
  | _ => { out := .throw { code := 0 } }

def gUser (id : Nat) (_ : Val) (_ : View) : UserResult := gR (id / 2)

/-- `fa = IO.raiseError(E2)` (code `nat 0`), `fin = IO.delay(emit 3)` (other codes). -/
def gIoOf : Val → IO
  | .nat 0 => .error { code := 2 }
  | _ => .delay (.user 2)

def gDisp (id : Nat) (a : Val) (v : View) : UserResult :=
  match BLam.ofId? id with
  | some l => call gUser gIoOf l a v
  | none => gUser id a v

def gEnv : UserEnv where
  call id a refs := gDisp id a { refs }
  callV := gDisp

theorem gEnv_even (id : Nat) (hid : id % 2 = 0) (a : Val) (v : View) : gEnv.callV id a v = gR (id / 2) := by
  show gDisp id a v = _
  simp [gDisp, BLam.ofId?_even hid, gUser]

theorem captured2 : WF.captured 2 = [] := by decide +kernel

theorem gR_ok (n : Nat) (R : Handle → Prop) (v : View) : WF.ResultOK isLib R v (gR n) := by
  match n with
  | 0 | 1 | 2 => simp [gR, WF.ResultOK, WF.EffectsOK, WF.OutOK, WF.progOK, WF.fnOK, WF.sub, Val.handles,
      captured2]
  | _ + 3 => simp [gR, WF.ResultOK, WF.EffectsOK, WF.OutOK]

theorem gWf (p : IO) (hp : WF.progOK isLib (fun h => ([] : List Handle).contains h) p = true) :
    WellFormed isLib [] gEnv p := by
  refine ⟨hp, fun id hid arg v => ⟨fun w _ => ?_, ?_⟩, ?_⟩
  · rw [gEnv_even id hid, gEnv_even id hid]
  · rw [gEnv_even id hid]; exact gR_ok _ _ _
  · refine WF.pollOpaque_of_const gEnv (fun id => gR (id / 2)) [2, 4]
      { out := .throw { code := 0 } } (fun id arg v hid => gEnv_even id hid arg v)
      (by decide +kernel) ?_ ?_ (fun _ _ => rfl)
    · intro id hid hk
      simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hk
      obtain h | h : id / 2 = 0 ∨ 3 ≤ id / 2 := by omega
      · simp only [h]; rfl
      · obtain ⟨k, hk⟩ := Nat.exists_eq_add_of_le h
        simp only [hk, show 3 + k = k + 3 by omega]; rfl
    · intro σ _ k hk
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hk
      rcases hk with rfl | rfl <;>
        simp [gR, WF.rnResult, WF.rnEffect, WF.rnVal, WF.rnIO, WF.rnFn_user_of_all σ 2 (by decide +kernel)]

def gObs : Obs := { summary := .done (.errored { code := 2 }), out := [.nat 3], refs := [], reports := [] }

/-- All hypotheses of the law hold together; the left side runs the finalizer and ends
`Errored(E2)`. -/
theorem guaranteeIsGuaranteeCase_satisfiable :
    ∃ (env : UserEnv) (ioOf : Val → IO) (s f : Val) (k : Nat),
      LibEnv env ioOf ∧ IOI.Lam.constProg env k (ioOf f) ∧
      WellFormed isLib [] env (ioOf s) ∧ WellFormed isLib [] env (ioOf f) ∧
      WellFormed isLib [] env (guaranteeIO (.ext s) (.ext f)) ∧
      WellFormed isLib [] env (guaranteeCaseIO (.ext s) k) ∧
      outcomesP {} counterMaskModel env (guaranteeIO (.ext s) (.ext f)) gObs := by
  have hl : outcomesPList {} counterMaskModel gEnv 200 (guaranteeIO (.ext (.nat 0)) (.ext (.nat 1)))
      = some [gObs] := by decide +kernel
  refine ⟨gEnv, gIoOf, .nat 0, .nat 1, 4, libEnv_of_dispatch gEnv gIoOf gUser (fun _ _ _ => rfl),
    fun a v => gEnv_even 4 rfl a v, gWf _ (by decide +kernel), gWf _ (by decide +kernel),
    gWf _ (by decide +kernel), gWf _ (by decide +kernel), ?_⟩
  exact (outcomesPList_sound {} counterMaskModel gEnv hl gObs).mpr (by simp)

end CatsEffectInLean.Proofs.Phase6.BracketWitness
