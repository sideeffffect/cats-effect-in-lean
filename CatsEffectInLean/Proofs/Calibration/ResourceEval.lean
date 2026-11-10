import CatsEffectInLean.Props.Calibration.ResourceEval
import CatsEffectInLean.Proofs.IO.MonadCancelLaws
import CatsEffectInLean.Model.EnumP

/-!
# Refutation of `resourceEvalPreservesUncancelable` (CE-0002)

Witness (case C of `reproducers/CE-0002/Repro.scala`):

* `g = IO.canceled`, so `fa = IO.uncancelable(_ => IO.canceled)`. `fa` alone succeeds: the
  cancel request waits for the end of the mask, and nothing after it checks.
* `alloc = Resource.eval(fa).allocatedCase` = `fa.flatMap(evalK)` (`Resource.scala:526-527`).
  After `fa`, the `flatMap` goes on in the run loop, which sees the pending cancel with no
  mask: outcome `Canceled`.
* `IO.uncancelable(_ => alloc)`: the same steps under a mask: outcome
  `Succeeded((), _ => F.unit)`.

The witness has one fiber. So preemption only splits its run into more tasks; it does not
change the result.

Proof shape: `exploreP` (`CatsEffectInLean/Model/EnumP.lean`) lists all reachable states of
each side under the preemptive scheduler (26 and 34 states). The list is closed under every
choice (`preempt`, every `pick`), so it holds every run of any fuel and any choice list. Left
side: the only observation is `Canceled` (empty trace). Right side: the only observation is
`Succeeded(...)`. `checkNotEqvP` checks this; `decide +kernel` evaluates it.

Fixed-twin check (decision 39): `CatsEffectInLean/Proofs/Calibration/ResourceEvalFixed.lean`.
-/

namespace CatsEffectInLean.Proofs.Calibration

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Resource
open CatsEffectInLean.Props.Calibration
open CatsEffectInLean.Proofs.IO.MonadCancelLaws

namespace ResourceEvalWitness

/-- `fa = IO.uncancelable(_ => IO.canceled)`; the body is user function 0. -/
def fa : IO := IOI.uncancelable (uid 0)

/-- `Resource.eval(fa).allocatedCase` (`Resource.scala:526-527`, `:530`). -/
def alloc : IO := .flatMap fa (.user 279459022985)

/-- The literal id is the id of the closure `evalK [] unit`. -/
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

/-- The exact outcome sets with preemption: left side `{Canceled}`. -/
theorem lhs_outcomesP :
    outcomesPList {} counterMaskModel r.toEnv 200 alloc = some [canceledObs] := by
  decide +kernel

/-- Right side `{Succeeded((), _ => F.unit)}`. -/
theorem rhs_outcomesP :
    outcomesPList {} counterMaskModel r.toEnv 200 (IOI.uncancelable (uid 1)) = some [succObs] := by
  decide +kernel

/-- The two sides differ under `EqvP` (all schedules with preemption). -/
theorem not_eqvP : ¬ EqvP {} counterMaskModel r.toEnv alloc (IOI.uncancelable (uid 1)) :=
  not_eqvP_of_checkNotEqvP {} counterMaskModel r.toEnv (bound := 200) (by decide +kernel)

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
  exact not_eqvP (h r 0 1 .canceled alloc (fun _ _ => rfl) allocatedCase_eq (fun _ _ => rfl)
    alloc_wellFormed rhs_wellFormed)

end CatsEffectInLean.Proofs.Calibration
