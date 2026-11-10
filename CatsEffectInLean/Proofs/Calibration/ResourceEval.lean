import CatsEffectInLean.Props.Calibration.ResourceEval
import CatsEffectInLean.Proofs.IO.MonadCancelLaws

/-!
# Refutation of `resourceEvalPreservesUncancelable` (CE-0002)

Witness (case C of `reproducers/CE-0002/Repro.scala`):

* `g = IO.canceled`, so `fa = IO.uncancelable(_ => IO.canceled)`. `fa` alone succeeds: the
  cancel request waits for the end of the mask, and nothing after it checks.
* `alloc = Resource.eval(fa).allocatedCase` = `fa.flatMap(evalK)` (`Resource.scala:526-527`).
  After `fa`, the `flatMap` goes on in the run loop, which sees the pending cancel with no
  mask: outcome `Canceled` (7 micro-steps).
* `IO.uncancelable(_ => alloc)`: the same steps under a mask: outcome
  `Succeeded((), _ => F.unit)` (8 micro-steps).

Proof shape (as `Proofs/IO/MonadCancelLaws.lean`): the left side has exactly one observation
(`Canceled`, empty trace) for every fuel and every pick list. The right side has the
observation `Succeeded(...)` at fuel 8. So the outcome sets differ.

Wrong-function test: with the fix of upstream PR #4630 (`poll(fa).flatMap(...)` inside one
`F.uncancelable`), both sides give `Succeeded` (`Model/ResourceExamples.lean`,
`fixed_lhs`, `fixed_rhs`), so this witness does not refute the fixed code.
-/

namespace CatsEffectInLean.Proofs.Calibration

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Props.Calibration
open CatsEffectInLean.Proofs.IO.MonadCancelLaws

/-- A halted run stays halted: more fuel gives the same state. (With a free fuel, `rfl` does not
evaluate runs that call the closures of `Model/Resource.lean`; with fuel `7` it does.) -/
theorem runSchedState_add {M : Type} (cfg : Config) (mm : MaskModel M) (env : UserEnv)
    (mt n k : Nat) (cs : List RChoice) (s : Sched M)
    (h : (runSchedState cfg mm env mt n cs s).halt ≠ none) :
    runSchedState cfg mm env mt (n + k) cs s = runSchedState cfg mm env mt n cs s := by
  induction n generalizing cs s with
  | zero =>
    simp only [runSchedState] at h
    cases k with
    | zero => rfl
    | succ k =>
      cases hs : s.halt with
      | none => exact absurd hs h
      | some _ => simp [runSchedState, hs]
  | succ n ih =>
    rw [Nat.add_right_comm]
    cases hs : s.halt with
    | some _ => simp [runSchedState, hs]
    | none =>
      simp only [runSchedState, hs] at h ⊢
      exact ih _ _ h

namespace ResourceEvalWitness

/-- `fa = IO.uncancelable(_ => IO.canceled)`; the body is user function 0. -/
def fa : IO := IOI.uncancelable (uid 0)

/-- `Resource.eval(fa).allocatedCase` (`Resource.scala:526-527`, `:530`). -/
def alloc : IO := .flatMap fa (.user 279459022985)

/-- The literal id is the id of the closure `evalK [] unit`. A literal lets `rfl` evaluate runs
with a free fuel (the elaborator does not reduce `Nat.mod` of a non-literal term). -/
theorem alloc_eq : alloc = .flatMap fa (cloFn (.evalK [] .unit)) := by decide +kernel

/-- User code: 0 is `_ => IO.canceled`, 1 is `_ => alloc`. -/
def user : UserEnv where
  call id _ _ := match id with
    | 0 => { out := .prog .canceled }
    | 1 => { out := .prog alloc }
    | _ => { out := .throw { code := 0 } }

/-- The witness environment. No `Bind`, `make` or release code is used. -/
def r : REnv where
  user := user
  bind _ _ := .error { code := 0 }
  acquire _ := .pure .unit
  release _ _ := .ok (.pure .unit)

/-- The observation of `IO.uncancelable(_ => alloc)`. -/
def succObs : Obs :=
  { summary := .done (.succeeded (.pair .unit RelFn.unit.toVal)), out := [], refs := [],
    reports := [] }

theorem allocatedCase_eq : allocatedCase r (Res.evalOf (IOI.uncancelable (uid 0))) = .ok alloc := by
  rw [alloc_eq]; rfl

theorem lhs_runs_nil (fuel : Nat) :
    runObs {} counterMaskModel r.toEnv fuel [] alloc = none ∨
    runObs {} counterMaskModel r.toEnv fuel [] alloc = some canceledObs := by
  match fuel with
  | 0 | 1 | 2 | 3 | 4 | 5 | 6 => exact Or.inl (by decide +kernel)
  | f + 7 =>
    refine Or.inr ?_
    have h7 : (runSchedState {} counterMaskModel r.toEnv (f + 7) 7 []
        (Sched.init counterMaskModel alloc)).obs = some canceledObs := rfl
    unfold runObs
    rw [Nat.add_comm f 7, runSchedState_add _ _ _ _ _ _ _ _ (by
      intro hn; rw [Nat.add_comm 7 f] at hn; simp [Sched.obs, hn] at h7)]
    rw [Nat.add_comm 7 f]; exact h7

theorem lhs_runs_pick (fuel : Nat) (rest : List RChoice) :
    runObs {} counterMaskModel r.toEnv fuel (.pick 0 :: rest) alloc = none ∨
    runObs {} counterMaskModel r.toEnv fuel (.pick 0 :: rest) alloc = some canceledObs := by
  match fuel with
  | 0 => exact Or.inl rfl
  | 1 => exact Or.inl rfl
  | 2 => exact Or.inl rfl
  | 3 => exact Or.inl rfl
  | 4 => exact Or.inl rfl
  | 5 => exact Or.inl rfl
  | 6 => exact Or.inl rfl
  | f + 7 =>
    refine Or.inr ?_
    have h7 : (runSchedState {} counterMaskModel r.toEnv (f + 7) 7 (.pick 0 :: rest)
        (Sched.init counterMaskModel alloc)).obs = some canceledObs := rfl
    unfold runObs
    rw [Nat.add_comm f 7, runSchedState_add _ _ _ _ _ _ _ _ (by
      intro hn; rw [Nat.add_comm 7 f] at hn; simp [Sched.obs, hn] at h7)]
    rw [Nat.add_comm 7 f]; exact h7

theorem rhs_succ : runObs {} counterMaskModel r.toEnv 8 [] (IOI.uncancelable (uid 1)) =
    some succObs := by
  decide +kernel

/-! ### The witness is well-formed -/

theorem ids_ok : isLib 279459022985 = true ∧ WF.captured 279459022985 = [] ∧
    WF.captured 0 = [] ∧ WF.captured 2 = [] := by
  decide +kernel

/-- User code (even ids) of `r.toEnv` passes `CallOK`: it ignores the view, has no effects, and
returns `IO.canceled`, `alloc` (only library closures without handles), or a throw. -/
theorem r_calls (id : Nat) (hid : id % 2 = 0) (arg : Val) (v : View) :
    WF.CallOK isLib [] r.toEnv id arg v := by
  obtain ⟨hl, hc, hc0, _⟩ := ids_ok
  have he : ∀ w, r.toEnv.callV id arg w = user.call (id / 2) arg w.refs := by
    intro w; simp [REnv.toEnv, REnv.callV, hid, r]; rfl
  refine ⟨fun w _ => ?_, ?_⟩
  · rw [he, he]
    rcases id / 2 with _ | _ | k <;> rfl
  · rw [he]
    rcases id / 2 with _ | _ | k <;>
      simp [user, WF.ResultOK, WF.EffectsOK, WF.OutOK, WF.progOK, WF.fnOK, WF.sub, alloc, fa,
        IOI.uncancelable, uid, hl, hc, hc0]

theorem r_wellFormed (p : IO) (hp : WF.progOK isLib (fun h => ([] : List Handle).contains h) p = true) :
    r.WellFormed p := by
  refine ⟨⟨hp, fun id hid arg v => r_calls id hid arg v⟩, fun _ => rfl, ?_, ?_⟩
  · intro _ _ q h; cases h; rfl
  · intro _ _ _ h; cases h

theorem alloc_wellFormed : r.WellFormed alloc := r_wellFormed alloc (by decide +kernel)

theorem rhs_wellFormed : r.WellFormed (IOI.uncancelable (uid 1)) :=
  r_wellFormed _ (by decide +kernel)

end ResourceEvalWitness

open ResourceEvalWitness in
theorem resourceEvalPreservesUncancelable_refuted : ¬ resourceEvalPreservesUncancelable := by
  intro h
  have hE := h r 0 1 .canceled alloc (fun _ _ => rfl) allocatedCase_eq (fun _ _ => rfl)
    alloc_wellFormed rhs_wellFormed
  have hR : outcomes {} counterMaskModel r.toEnv (IOI.uncancelable (uid 1)) succObs :=
    ⟨8, [], fun _ hc => absurd hc List.not_mem_nil, rhs_succ⟩
  obtain ⟨fuel, cs, hcs, heq⟩ := (hE succObs).2 hR
  rcases runs_of_nil_pick r.toEnv alloc canceledObs lhs_runs_nil lhs_runs_pick fuel cs hcs
    with h' | h'
  · rw [h'] at heq; cases heq
  · rw [h'] at heq
    exact absurd (Option.some.inj heq) (by decide)

end CatsEffectInLean.Proofs.Calibration
