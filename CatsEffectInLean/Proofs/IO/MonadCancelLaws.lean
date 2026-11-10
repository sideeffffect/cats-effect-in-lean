import CatsEffectInLean.Props.IO.MonadCancelLaws
import CatsEffectInLean.Model.EnumP

/-!
# Proofs of `MonadCancel` laws for `IO`

Two laws where `fa` never runs: `canceledAssociatesLeftOverFlatMap` and
`forceRCanceledShortCircuits`. Both sides of each law cancel the root fiber before `fa` can
run.

## Under `EqvP` (the registered statements)

The preemptive scheduler reads one choice at each micro-step, so a run depends on the whole
choice list. The proof uses a finite family of states (`runSchedStateP_family`,
`CatsEffectInLean/Model/EnumP.lean`):

1. The family: `famSt` of a list of choice lists (`true` = `preempt`, `false` = `pick 0`).
   The lists come from `exploreTable` on a closed instance (`#eval`).
2. For each family state that can go on, `preempt` and every `pick m` lead to a family state
   (`rfl`). One fiber only, so at most one task is ready and `pick m` acts as `pick 0`
   (`tickP_pick_single`).
3. Each family state has no observation, or the observation `Canceled` (`rfl`/`decide`).

`env`, `fa` and the ids stay free variables: the runs never call user code.

## Under `Eqv` (the old statements, kept as lemmas)

1. `runObs_pick`: the first choice `pick n` acts as `pick 0` (one ready task, `n mod 1 = 0`).
2. Each later step of these runs ignores the choice list (a task runs, or the root outcome is
   checked). So for a pick-only list the run depends only on the fuel.
3. Each concrete run is checked by `rfl` (kernel reduction). For `fuel ≥ 6` the term `f + 6`
   reduces, and the halted state stays fixed.

Result (both): each side has exactly one observation, `Canceled` with an empty trace, no
`Ref` cell, and no reported error. So the outcome sets are equal.

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

/-- The law under the replay `Eqv` (no preemption), without the `WellFormedIO` hypotheses. -/
theorem canceledAssociatesLeftOverFlatMap_eqv (env : UserEnv) (fa : IO) (k : Nat)
    (_ : IOI.Lam.constProg env k (IOI.void fa)) :
    Eqv {} counterMaskModel env (IOI.flatMap IOI.canceled (.user k)) IOI.canceled := by
  have hl := outcomes_eq_of_runs {} counterMaskModel env (canceledThen k) canceledObs
    (runs_of_nil_pick env _ _ (canceledThen_runs_nil env k) (canceledThen_runs_pick env k))
    ⟨5, rfl⟩
  have hr := outcomes_eq_of_runs {} counterMaskModel env IOI.canceled canceledObs
    (runs_of_nil_pick env _ _ (canceled_runs_nil env) (canceled_runs_pick env))
    ⟨4, rfl⟩
  intro o
  rw [hl o, hr o]

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

/-- The law under the replay `Eqv` (as `canceledAssociatesLeftOverFlatMap_eqv`). -/
theorem forceRCanceledShortCircuits_eqv (env : UserEnv) (fa : IO) (h k k' : Nat)
    (_ : IOI.Lam.constProg env h (IOI.pure .unit)) (_ : IOI.Lam.constProg env k fa)
    (_ : IOI.Lam.constProg env k' fa) :
    Eqv {} counterMaskModel env (IOI.forceR IOI.canceled (.user h) (.user k))
      (IOI.productR IOI.canceled (.user k')) := by
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

/-! ## Under `EqvP`: families of states -/

/-- The choice lists of the family of `F.canceled >> fa.void` (`exploreTable`, 13 states). -/
def pathsCanceledThen : List (List Bool) :=
  [[], [false], [false, true], [false, false], [false, true, false], [false, false, true],
   [false, false, false], [false, true, false, false], [false, false, true, false],
   [false, false, false, false], [false, true, false, false, false],
   [false, false, true, false, false], [false, false, false, false, false]]

def npCanceledThen : List Nat := [0, 2, 2, 5, 2, 5, 6, 5, 5, 9, 10, 11, 12]
def nkCanceledThen : List Nat := [1, 3, 4, 6, 7, 8, 9, 10, 11, 12, 9, 9, 12]

/-- The choice lists of the family of `F.canceled` (8 states). -/
def pathsCanceled : List (List Bool) :=
  [[], [false], [false, true], [false, false], [false, true, false], [false, false, false],
   [false, true, false, false], [false, false, false, false]]

def npCanceled : List Nat := [0, 2, 2, 3, 2, 5, 6, 7]
def nkCanceled : List Nat := [1, 3, 4, 5, 6, 7, 5, 7]

/-- The choice lists of the family of `F.forceR(F.canceled)(fa)` (19 states). -/
def pathsForceR : List (List Bool) :=
  [[], [false], [false, true], [false, false], [false, true, false], [false, false, true],
   [false, false, false], [false, true, false, false], [false, false, true, false],
   [false, false, false, true], [false, false, false, false],
   [false, true, false, false, false], [false, false, true, false, false],
   [false, false, false, true, false], [false, false, false, false, false],
   [false, true, false, false, false, false], [false, false, true, false, false, false],
   [false, false, false, true, false, false], [false, false, false, false, false, false]]

def npForceR : List Nat := [0, 2, 2, 5, 2, 5, 9, 5, 5, 9, 10, 9, 9, 9, 14, 15, 16, 17, 18]
def nkForceR : List Nat := [1, 3, 4, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17, 18, 14, 14, 14, 18]

section FamilyP
variable (env : UserEnv)

/-- The family state `i` of program `io` with choice lists `ps`. -/
abbrev fst (io : IO) (ps : List (List Bool)) (i : Nat) : Sched CounterMask :=
  famSt {} counterMaskModel env io ps i

set_option maxHeartbeats 4000000 in
theorem canceledThenP (k : Nat) :
    ∀ o, outcomesP {} counterMaskModel env (canceledThen k) o ↔ o = canceledObs := by
  refine outcomesP_single_of_family {} counterMaskModel env 13
    (fst env (canceledThen k) pathsCanceledThen)
    (fun i => npCanceledThen.getD i 0) (fun i => nkCanceledThen.getD i 0)
    (by decide) ?_ ?_ (by decide) rfl ?_ ⟨5, rfl⟩
  · intro i hi hh
    rcases i with _|_|_|_|_|_|_|_|_|_|_|_|_|i
    all_goals first | rfl | omega
  · intro i hi hh m
    rcases i with _|_|_|_|_|_|_|_|_|_|_|_|_|i
    all_goals first
      | exact (tickP_pick_single _ _ _ _ m (Nat.le_of_ble_eq_true rfl)).trans rfl
      | omega
  · intro i hi
    rcases i with _|_|_|_|_|_|_|_|_|_|_|_|_|i
    all_goals first | exact Or.inl rfl | exact Or.inr rfl | omega

set_option maxHeartbeats 4000000 in
theorem canceledP :
    ∀ o, outcomesP {} counterMaskModel env IOI.canceled o ↔ o = canceledObs := by
  refine outcomesP_single_of_family {} counterMaskModel env 8
    (fst env IOI.canceled pathsCanceled)
    (fun i => npCanceled.getD i 0) (fun i => nkCanceled.getD i 0)
    (by decide) ?_ ?_ (by decide) rfl ?_ ⟨4, rfl⟩
  · intro i hi hh
    rcases i with _|_|_|_|_|_|_|_|i
    all_goals first | rfl | omega
  · intro i hi hh m
    rcases i with _|_|_|_|_|_|_|_|i
    all_goals first
      | exact (tickP_pick_single _ _ _ _ m (Nat.le_of_ble_eq_true rfl)).trans rfl
      | omega
  · intro i hi
    rcases i with _|_|_|_|_|_|_|_|i
    all_goals first | exact Or.inl rfl | exact Or.inr rfl | omega

set_option maxHeartbeats 8000000 in
theorem forceRCanceledP (h k : Nat) :
    ∀ o, outcomesP {} counterMaskModel env (forceRCanceled h k) o ↔ o = canceledObs := by
  refine outcomesP_single_of_family {} counterMaskModel env 19
    (fst env (forceRCanceled h k) pathsForceR)
    (fun i => npForceR.getD i 0) (fun i => nkForceR.getD i 0)
    (by decide) ?_ ?_ (by decide) rfl ?_ ⟨6, rfl⟩
  · intro i hi hh
    rcases i with _|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|i
    all_goals first | rfl | omega
  · intro i hi hh m
    rcases i with _|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|i
    all_goals first
      | exact (tickP_pick_single _ _ _ _ m (Nat.le_of_ble_eq_true rfl)).trans rfl
      | omega
  · intro i hi
    rcases i with _|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|i
    all_goals first | exact Or.inl rfl | exact Or.inr rfl | omega

end FamilyP

/-- The law without the `WellFormedIO` hypotheses: it holds for all model programs and all user
code, also for programs that Scala cannot write. -/
theorem canceledAssociatesLeftOverFlatMap_all (env : UserEnv) (fa : IO) (k : Nat)
    (_ : IOI.Lam.constProg env k (IOI.void fa)) :
    IOEqv env (IOI.flatMap IOI.canceled (.user k)) IOI.canceled := by
  intro o
  rw [canceledThenP env k o, canceledP env o]

theorem canceledAssociatesLeftOverFlatMap_proven : canceledAssociatesLeftOverFlatMap :=
  fun env fa k hk _ _ => canceledAssociatesLeftOverFlatMap_all env fa k hk

/-- The law without the `WellFormedIO` hypotheses (as `canceledAssociatesLeftOverFlatMap_all`). -/
theorem forceRCanceledShortCircuits_all (env : UserEnv) (fa : IO) (h k k' : Nat)
    (_ : IOI.Lam.constProg env h (IOI.pure .unit)) (_ : IOI.Lam.constProg env k fa)
    (_ : IOI.Lam.constProg env k' fa) :
    IOEqv env (IOI.forceR IOI.canceled (.user h) (.user k)) (IOI.productR IOI.canceled (.user k')) := by
  intro o
  -- the right side is `canceledThen k'`
  have h2 : outcomesP {} counterMaskModel env (IOI.productR IOI.canceled (.user k')) o ↔
      o = canceledObs := canceledThenP env k' o
  exact (forceRCanceledP env h k o).trans h2.symm

theorem forceRCanceledShortCircuits_proven : forceRCanceledShortCircuits :=
  fun env fa h k k' hh hk hk' _ _ => forceRCanceledShortCircuits_all env fa h k k' hh hk hk'

end CatsEffectInLean.Proofs.IO.MonadCancelLaws
