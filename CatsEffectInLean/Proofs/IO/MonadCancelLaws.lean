import CatsEffectInLean.Props.IO.MonadCancelLaws

/-!
# Proofs of `MonadCancel` laws for `IO`

Two laws where `fa` never runs: `canceledAssociatesLeftOverFlatMap` and
`forceRCanceledShortCircuits`. Both sides of each law cancel the root fiber before `fa` can
run. The proof computes every run:

1. `runObs_pick`: the first choice `pick n` acts as `pick 0` (one ready task, `n mod 1 = 0`).
2. Each later step of these runs ignores the choice list (a task runs, or the root outcome is
   checked). So for a pick-only list the run depends only on the fuel.
3. Each concrete run is checked by `rfl` (kernel reduction). `env`, `fa` and the ids stay free
   variables: the runs never call user code. For `fuel ≥ 6` the term `f + 6` reduces, and the
   halted state stays fixed.

Result: each side has exactly one observation, `Canceled` with an empty trace, no `Ref`
cell, and no reported error. So the outcome sets are equal.

Wrong-function test. `IOI.canceled := IOI.unit` breaks `canceledAssociatesLeftOverFlatMap`
(the left side runs `fa.void`; with `fa` that emits, the traces differ). `forceR a b := b`
breaks `forceRCanceledShortCircuits` (left side `fa`, right side `Canceled`). The
hypotheses on `env` are not used: the lambdas are never called, which is the content of the
laws.
-/

namespace CatsEffectInLean.Proofs.IO.MonadCancelLaws

open CatsEffectInLean.Model
open CatsEffectInLean.Props.IO.MonadCancelLaws

/-! ## Run lemmas -/

theorem tick_init_pick {M : Type} (cfg : Config) (mm : MaskModel M) (env : UserEnv) (io : IO)
    (n mt : Nat) (r : List RChoice) (hmt : 0 < mt) :
    (Sched.init mm io).tick cfg mm env mt (.pick n :: r) =
    (Sched.init mm io).tick cfg mm env mt (.pick 0 :: r) := by
  have h1 : ¬ mt ≤ 0 := by omega
  simp [Sched.tick, Sched.init, Fiber.new, h1, Nat.mod_one]

/-- The first choice `pick n` from the initial state acts as `pick 0`: one task is ready. -/
theorem runObs_pick {M : Type} (cfg : Config) (mm : MaskModel M) (env : UserEnv) (io : IO)
    (n f : Nat) (r : List RChoice) :
    runObs cfg mm env (f + 1) (.pick n :: r) io = runObs cfg mm env (f + 1) (.pick 0 :: r) io := by
  have h : ∀ c : RChoice, c = .pick n ∨ c = .pick 0 →
      runSchedState cfg mm env (f + 1) (f + 1) (c :: r) (Sched.init mm io) =
      runSchedState cfg mm env (f + 1) f
        ((Sched.init mm io).tick cfg mm env (f + 1) (c :: r)).2
        ((Sched.init mm io).tick cfg mm env (f + 1) (c :: r)).1 := by
    intro c _
    rfl
  unfold runObs
  rw [h _ (Or.inl rfl), h _ (Or.inr rfl), tick_init_pick cfg mm env io n (f + 1) r (by omega)]

/-- The only observation of both sides. -/
def canceledObs : Obs := { summary := .done .canceled, out := [], refs := [], reports := [] }

/-- From a run lemma for each fuel to the outcome set. -/
theorem outcomes_eq_of_runs {M : Type} (cfg : Config) (mm : MaskModel M) (env : UserEnv)
    (io : IO) (o₀ : Obs)
    (hrun : ∀ fuel cs, (∀ c ∈ cs, c.isPick = true) →
      runObs cfg mm env fuel cs io = none ∨ runObs cfg mm env fuel cs io = some o₀)
    (hwit : ∃ fuel, runObs cfg mm env fuel [] io = some o₀) :
    ∀ o, outcomes cfg mm env io o ↔ o = o₀ := by
  intro o
  constructor
  · rintro ⟨fuel, cs, hcs, h⟩
    rcases hrun fuel cs hcs with h' | h'
    · rw [h'] at h; cases h
    · rw [h'] at h; cases h; rfl
  · rintro rfl
    obtain ⟨fuel, h⟩ := hwit
    exact ⟨fuel, [], ⟨fun _ hc => absurd hc List.not_mem_nil, h⟩⟩

/-! ## `canceledAssociatesLeftOverFlatMap` -/

section CanceledLeft
variable (env : UserEnv) (k : Nat)

/-- `F.canceled >> fa.void`. -/
abbrev canceledThen : IO := IOI.flatMap IOI.canceled (.user k)

theorem canceledThen_runs_nil (fuel : Nat) :
    runObs {} counterMaskModel env fuel [] (canceledThen k) = none ∨
    runObs {} counterMaskModel env fuel [] (canceledThen k) = some canceledObs := by
  match fuel with
  | 0 | 1 | 2 | 3 | 4 => exact Or.inl rfl
  | 5 => exact Or.inr rfl
  | f + 6 => exact Or.inr rfl

theorem canceledThen_runs_pick (fuel : Nat) (r : List RChoice) :
    runObs {} counterMaskModel env fuel (.pick 0 :: r) (canceledThen k) = none ∨
    runObs {} counterMaskModel env fuel (.pick 0 :: r) (canceledThen k) = some canceledObs := by
  match fuel with
  | 0 | 1 | 2 | 3 | 4 => exact Or.inl rfl
  | 5 => exact Or.inr rfl
  | f + 6 => exact Or.inr rfl

theorem canceled_runs_nil (fuel : Nat) :
    runObs {} counterMaskModel env fuel [] IOI.canceled = none ∨
    runObs {} counterMaskModel env fuel [] IOI.canceled = some canceledObs := by
  match fuel with
  | 0 | 1 | 2 | 3 => exact Or.inl rfl
  | 4 => exact Or.inr rfl
  | f + 5 => exact Or.inr rfl

theorem canceled_runs_pick (fuel : Nat) (r : List RChoice) :
    runObs {} counterMaskModel env fuel (.pick 0 :: r) IOI.canceled = none ∨
    runObs {} counterMaskModel env fuel (.pick 0 :: r) IOI.canceled = some canceledObs := by
  match fuel with
  | 0 | 1 | 2 | 3 => exact Or.inl rfl
  | 4 => exact Or.inr rfl
  | f + 5 => exact Or.inr rfl

end CanceledLeft

/-- Turn the `[]` and `pick 0 :: r` run lemmas into a run lemma for every pick-only list. -/
theorem runs_of_nil_pick (env : UserEnv) (io : IO) (o₀ : Obs)
    (hnil : ∀ fuel, runObs {} counterMaskModel env fuel [] io = none ∨
      runObs {} counterMaskModel env fuel [] io = some o₀)
    (hpick : ∀ fuel r, runObs {} counterMaskModel env fuel (.pick 0 :: r) io = none ∨
      runObs {} counterMaskModel env fuel (.pick 0 :: r) io = some o₀) :
    ∀ fuel cs, (∀ c ∈ cs, c.isPick = true) →
      runObs {} counterMaskModel env fuel cs io = none ∨
      runObs {} counterMaskModel env fuel cs io = some o₀ := by
  intro fuel cs hcs
  match cs, fuel with
  | [], fuel => exact hnil fuel
  | .cancel _ :: _, _ => exact absurd (hcs _ List.mem_cons_self) (by simp [RChoice.isPick])
  | .pick _ :: _, 0 => exact Or.inl rfl
  | .pick n :: r, f + 1 =>
    rw [runObs_pick]
    exact hpick (f + 1) r

/-- The law without the `WellFormedIO` hypotheses: it holds for all model programs and all user
code, also for programs that Scala cannot write. -/
theorem canceledAssociatesLeftOverFlatMap_all (env : UserEnv) (fa : IO) (k : Nat)
    (_ : IOI.Lam.constProg env k (IOI.void fa)) :
    IOEqv env (IOI.flatMap IOI.canceled (.user k)) IOI.canceled := by
  have hl := outcomes_eq_of_runs {} counterMaskModel env (canceledThen k) canceledObs
    (runs_of_nil_pick env _ _ (canceledThen_runs_nil env k) (canceledThen_runs_pick env k))
    ⟨5, rfl⟩
  have hr := outcomes_eq_of_runs {} counterMaskModel env IOI.canceled canceledObs
    (runs_of_nil_pick env _ _ (canceled_runs_nil env) (canceled_runs_pick env))
    ⟨4, rfl⟩
  intro o
  rw [hl o, hr o]

theorem canceledAssociatesLeftOverFlatMap_proven : canceledAssociatesLeftOverFlatMap :=
  fun env fa k hk _ _ => canceledAssociatesLeftOverFlatMap_all env fa k hk

/-! ## `forceRCanceledShortCircuits` -/

section ForceR
variable (env : UserEnv) (h k k' : Nat)

/-- `F.forceR(F.canceled)(fa)`. -/
abbrev forceRCanceled : IO := IOI.forceR IOI.canceled (.user h) (.user k)

/-- `F.productR(F.canceled)(fa)`. -/
abbrev productRCanceled : IO := IOI.productR IOI.canceled (.user k')

-- `rfl` on the longest run needs more than the default heartbeats.
set_option maxHeartbeats 1000000 in
theorem forceRCanceled_runs_nil (fuel : Nat) :
    runObs {} counterMaskModel env fuel [] (forceRCanceled h k) = none ∨
    runObs {} counterMaskModel env fuel [] (forceRCanceled h k) = some canceledObs := by
  match fuel with
  | 0 | 1 | 2 | 3 | 4 | 5 => exact Or.inl rfl
  | 6 => exact Or.inr rfl
  | f + 7 => exact Or.inr rfl

set_option maxHeartbeats 1000000 in
theorem forceRCanceled_runs_pick (fuel : Nat) (r : List RChoice) :
    runObs {} counterMaskModel env fuel (.pick 0 :: r) (forceRCanceled h k) = none ∨
    runObs {} counterMaskModel env fuel (.pick 0 :: r) (forceRCanceled h k) = some canceledObs := by
  match fuel with
  | 0 | 1 | 2 | 3 | 4 | 5 => exact Or.inl rfl
  | 6 => exact Or.inr rfl
  | f + 7 => exact Or.inr rfl

end ForceR

/-- The law without the `WellFormedIO` hypotheses (as `canceledAssociatesLeftOverFlatMap_all`). -/
theorem forceRCanceledShortCircuits_all (env : UserEnv) (fa : IO) (h k k' : Nat)
    (_ : IOI.Lam.constProg env h (IOI.pure .unit)) (_ : IOI.Lam.constProg env k fa)
    (_ : IOI.Lam.constProg env k' fa) :
    IOEqv env (IOI.forceR IOI.canceled (.user h) (.user k)) (IOI.productR IOI.canceled (.user k')) := by
  have hl := outcomes_eq_of_runs {} counterMaskModel env (forceRCanceled h k) canceledObs
    (runs_of_nil_pick env _ _ (forceRCanceled_runs_nil env h k) (forceRCanceled_runs_pick env h k))
    ⟨6, rfl⟩
  -- the right side is `canceledThen k'`
  have hr := outcomes_eq_of_runs {} counterMaskModel env (canceledThen k') canceledObs
    (runs_of_nil_pick env _ _ (canceledThen_runs_nil env k') (canceledThen_runs_pick env k'))
    ⟨5, rfl⟩
  intro o
  rw [hl o]
  exact (hr o).symm

theorem forceRCanceledShortCircuits_proven : forceRCanceledShortCircuits :=
  fun env fa h k k' hh hk hk' _ _ => forceRCanceledShortCircuits_all env fa h k k' hh hk hk'

end CatsEffectInLean.Proofs.IO.MonadCancelLaws
