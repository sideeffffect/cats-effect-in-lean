import CatsEffectInLean.Props.Phase7.Supervisor

/-!
# `Supervisor`: satisfiability witnesses, wrong-function tests and the decision 63 battery

Phase 7, track V. Decision 53: for each statement of `Props/Phase7/Supervisor.lean`, one concrete
input meets every hypothesis (`IsOrder`, `cv ≤ 1`, `AllWF`, and the statement's own shape) and
reaches the interesting case of the conclusion (`*_sat`). Review rubric and decision 63: each
wrong variant of the mirror (`v ≠ 0`, not Cats Effect code, `Std/Supervisor.lean`) violates one
registered statement, as a theorem `¬ supXV v` (kernel-checked runs, `decide +kernel`).

The user programs are `IO.pure(())` (`p`) and `IO.never` (`nv`, the `Timeout.neverIO` closures,
the statement library). There is no user function: every even id throws (`u`). Map order: the
insertion order (`id`). Schedules: the default (`pick 0` at each step).

| Statement | Witness (`v = 0`) | Wrong variants (theorems) |
|---|---|---|
| `supNoLeak` | `aw = false`, a child that never ends: done, the child canceled (status 3) | 7 finalizer drops (11 restart ignores its flags: `SupervisorRestartWitness.lean`, separate CI job) |
| `supClosedNoRun` | a late `supervise`: done, flagged, never ran | 9 `add` ignores the close |
| `supRunsOnce` | a child canceled by the close: one start, one finalizer run | 4 `supervise` doubles |
| `supAwaitJoins` | `aw = true`, two children: done `Succeeded(())`, both status 2 | 1 raises, 3 drops, 5 factory raises, 12 cancels |
| `supNoDeadlock` | a child that supervises a grandchild: done | 2 `supervise` hangs, 6 factory hangs |
| `supRemoved` | `aw = true`, a finished child and a child that never ends: blocked, the map holds one live fiber | 10 `remove` never removes |
| `supCancels` | `aw = false`, a child that sleeps: done, status 3 | 8 `await = false` joins |
-/

namespace CatsEffectInLean.Proofs.Phase7.SupervisorWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Props.Phase7.Supervisor

/-- No user function: every user call throws. -/
def userR : UserResult := { out := .throw { code := 0 } }

def u : UserEnv := { call := fun _ _ _ => userR }

/-- `IO.pure(())`. -/
def p : IO := .pure .unit

/-- `IO.never`. -/
def nv : IO := Timeout.neverIO

/-- `IO.cede` (the body lets the children run before the close). -/
def c : IO := .cede

theorem callV_even (ho : List Val → List Val) (ws : List IO) (ps : List Nat) (b : IO) (id : Nat)
    (hid : id % 2 = 0) (a : Val) (v : View) : (env ho ws ps b u).callV id a v = userR := by
  have h1 : isLibId id = false := by simp [isLibId, hid]
  show CatsEffectInLean.Std.Supervisor.dispatch ho ioOf (harnessed ws ps b u) id a v = _
  simp [CatsEffectInLean.Std.Supervisor.dispatch, CatsEffectInLean.Std.Supervisor.dispatch.go,
    CatsEffectInLean.Std.Supervisor.SLam.ofId?, Bracket.BLam.ofId?, Race.ofId?, h1, harnessed,
    HLam.ofId?, u]

/-- `WellFormed` for a closed program that calls no user code. -/
theorem wf (ho : List Val → List Val) (ws : List IO) (ps : List Nat) (b : IO) (q : IO)
    (hq : WF.progOK supLib (fun h => ([] : List Handle).contains h) q = true) :
    WellFormed supLib [] (env ho ws ps b u) q := by
  refine ⟨hq, fun id hid arg v => ⟨fun w _ => ?_, ?_⟩, ?_⟩
  · rw [callV_even ho ws ps b id hid, callV_even ho ws ps b id hid]
  · rw [callV_even ho ws ps b id hid]; simp [userR, WF.ResultOK, WF.EffectsOK, WF.OutOK]
  · refine WF.pollOpaque_of_const (env ho ws ps b u) (fun _ => userR) [] userR
      (fun id arg v hid => callV_even ho ws ps b id hid arg v) (by decide) (fun _ _ _ => rfl) ?_ (fun _ _ => rfl)
    intro σ _ k hk
    simp at hk

theorem p_ok : WF.progOK supLib (fun h => ([] : List Handle).contains h) p = true := by decide +kernel
theorem nv_ok : WF.progOK supLib (fun h => ([] : List Handle).contains h) nv = true := by decide +kernel
theorem c_ok : WF.progOK supLib (fun h => ([] : List Handle).contains h) c = true := by decide +kernel
theorem sl_ok : WF.progOK supLib (fun h => ([] : List Handle).contains h) (.sleep 1) = true := by decide +kernel

theorem isOrder_id : IsOrder id := fun es => List.Perm.refl es

/-- `AllWF` for programs that each pass `progOK`. -/
theorem allWF_of (ho : List Val → List Val) (ws : List IO) (ps : List Nat) (b : IO)
    (h : ∀ q ∈ b :: ws, WF.progOK supLib (fun h => ([] : List Handle).contains h) q = true) :
    AllWF ho ws ps b u := fun q hq => wf ho ws ps b q (h q hq)

theorem ok_p_nv : ∀ q ∈ p :: [p, nv], WF.progOK supLib (fun h => ([] : List Handle).contains h) q = true := by
  intro q hq; simp only [List.mem_cons, List.not_mem_nil, or_false] at hq
  rcases hq with rfl | rfl | rfl <;> first | exact p_ok | exact nv_ok

theorem ok_nv : ∀ q ∈ p :: [nv], WF.progOK supLib (fun h => ([] : List Handle).contains h) q = true := by
  intro q hq; simp only [List.mem_cons, List.not_mem_nil, or_false] at hq
  rcases hq with rfl | rfl <;> first | exact p_ok | exact nv_ok

theorem ok_c_nv : ∀ q ∈ c :: [nv], WF.progOK supLib (fun h => ([] : List Handle).contains h) q = true := by
  intro q hq; simp only [List.mem_cons, List.not_mem_nil, or_false] at hq
  rcases hq with rfl | rfl <;> first | exact c_ok | exact nv_ok

theorem ok_c_sl : ∀ q ∈ c :: [Model.IO.sleep 1], WF.progOK supLib (fun h => ([] : List Handle).contains h) q = true := by
  intro q hq; simp only [List.mem_cons, List.not_mem_nil, or_false] at hq
  rcases hq with rfl | rfl <;> first | exact c_ok | exact sl_ok

theorem ok_p : ∀ q ∈ p :: [p], WF.progOK supLib (fun h => ([] : List Handle).contains h) q = true := by
  intro q hq; simp only [List.mem_cons, List.not_mem_nil, or_false] at hq
  rcases hq with rfl | rfl <;> exact p_ok

theorem ok_pp : ∀ q ∈ p :: [p, p], WF.progOK supLib (fun h => ([] : List Handle).contains h) q = true := by
  intro q hq; simp only [List.mem_cons, List.not_mem_nil, or_false] at hq
  rcases hq with rfl | rfl | rfl <;> exact p_ok

theorem ok_sl : ∀ q ∈ p :: [Model.IO.sleep 1], WF.progOK supLib (fun h => ([] : List Handle).contains h) q = true := by
  intro q hq; simp only [List.mem_cons, List.not_mem_nil, or_false] at hq
  rcases hq with rfl | rfl <;> first | exact p_ok | exact sl_ok

/-! ## Statement 1: `supNoLeak` -/

theorem noLeak_sat :
    AllWF id [nv] [0] c u ∧
      (run id false false 0 [nv] [0] c u 600 []).halt = some (.done (.succeeded .unit)) ∧
      status (run id false false 0 [nv] [0] c u 600 []) 0 = 3 :=
  ⟨allWF_of id _ _ _ ok_c_nv, by decide +kernel, by decide +kernel⟩

/-- Variant 7 (the finalizer drops its cancel/join): the root is done, the child still runs. -/
theorem noLeak_v7 : ¬ supNoLeakV 7 := by
  intro h
  have hd : (run id false false 0 [nv] [0] c u 600 [] 7).halt = some (.done (.succeeded .unit)) := by
    decide +kernel
  have hs : status (run id false false 0 [nv] [0] c u 600 [] 7) 0 = 1 := by decide +kernel
  exact h u id false false 0 [nv] [0] c isOrder_id (by decide) (allWF_of id _ _ _ ok_c_nv) 600 []
    _ hd 0 hs

/-! ## Statement 2: `supClosedNoRun` -/

theorem closedNoRun_sat :
    AllWF id [p] [late] p u ∧
      (run id false false 0 [p] [late] p u 600 []).halt = some (.done (.succeeded .unit)) ∧
      rejected (run id false false 0 [p] [late] p u 600 []) 0 = 1 ∧
      runs (run id false false 0 [p] [late] p u 600 []) 0 = 0 :=
  ⟨allWF_of id _ _ _ ok_p, by decide +kernel, by decide +kernel, by decide +kernel⟩

/-- Variant 9 (`add` ignores the close): a late `supervise` succeeds (no flag). -/
theorem closedNoRun_v9 : ¬ supClosedNoRunV 9 := by
  intro h
  have hd : (run id false false 0 [p] [late] p u 600 [] 9).halt = some (.done (.succeeded .unit)) := by
    decide +kernel
  have hr : rejected (run id false false 0 [p] [late] p u 600 [] 9) 0 = 0 := by decide +kernel
  have := (h u id false false 0 [p] [late] p isOrder_id (by decide) (allWF_of id _ _ _ ok_p) 600 [] 0).2
    hd rfl (by decide)
  omega

/-! ## Statement 3: `supRunsOnce` -/

theorem runsOnce_sat :
    AllWF id [nv] [0] c u ∧
      runs (run id false false 0 [nv] [0] c u 600 []) 0 = 1 ∧
      fins (run id false false 0 [nv] [0] c u 600 []) 0 = 1 :=
  ⟨allWF_of id _ _ _ ok_c_nv, by decide +kernel, by decide +kernel⟩

/-- Variant 4 (`supervise` doubles): the child's user code runs twice. -/
theorem runsOnce_v4 : ¬ supRunsOnceV 4 := by
  intro h
  have hr : runs (run id false false 0 [p] [0] p u 600 [] 4) 0 = 2 := by decide +kernel
  have := (h u id false 0 [p] [0] p isOrder_id (by decide) (allWF_of id _ _ _ ok_p) 600 [] 0).1
  omega

/-! ## Statement 4: `supAwaitJoins` -/

theorem awaitJoins_sat :
    AllWF id (List.replicate 2 (.pure .unit)) (List.replicate 2 0) (.pure .unit) u ∧
      (run id true false 0 (List.replicate 2 (.pure .unit)) (List.replicate 2 0) (.pure .unit) u 900 []).halt
        = some (.done (.succeeded .unit)) ∧
      status (run id true false 0 (List.replicate 2 (.pure .unit)) (List.replicate 2 0) (.pure .unit) u 900 []) 0 = 2 ∧
      status (run id true false 0 (List.replicate 2 (.pure .unit)) (List.replicate 2 0) (.pure .unit) u 900 []) 1 = 2 :=
  ⟨allWF_of id _ _ _ ok_pp, by decide +kernel, by decide +kernel, by decide +kernel⟩

/-- A variant that ends the root `done` with a child at a status other than 2 breaks
statement 4 (one child, `aw = true`). -/
theorem awaitJoins_break (v x : Nat) (oc : Outcome)
    (hd : (run id true false 0 (List.replicate 1 (.pure .unit)) (List.replicate 1 0) (.pure .unit) u 600 [] v).halt
      = some (.done oc))
    (hs : oc ≠ .succeeded .unit ∨
      status (run id true false 0 (List.replicate 1 (.pure .unit)) (List.replicate 1 0) (.pure .unit) u 600 [] v) 0 = x ∧
        x ≠ 2) :
    ¬ supAwaitJoinsV v := by
  intro h
  have := h u id 0 1 isOrder_id (by decide) (allWF_of id _ _ _ ok_p) 600 [] oc hd
  rcases hs with hs | ⟨hs, hx⟩
  · exact hs this.1
  · exact hx (hs ▸ this.2 0 (by decide))

/-- Variant 1 (`supervise` raises): the child never runs. -/
theorem awaitJoins_v1 : ¬ supAwaitJoinsV 1 :=
  awaitJoins_break 1 0 (.succeeded .unit) (by decide +kernel) (.inr ⟨by decide +kernel, by decide⟩)

/-- Variant 3 (`supervise` drops `fa`): the child never runs. -/
theorem awaitJoins_v3 : ¬ supAwaitJoinsV 3 :=
  awaitJoins_break 3 0 (.succeeded .unit) (by decide +kernel) (.inr ⟨by decide +kernel, by decide⟩)

/-- Variant 5 (the factory raises): the root ends `Errored`. -/
theorem awaitJoins_v5 : ¬ supAwaitJoinsV 5 :=
  awaitJoins_break 5 0 (.errored CatsEffectInLean.Std.Supervisor.battErr) (by decide +kernel) (.inl (by decide))

/-- Variant 12 (`await = true` cancels): the child is canceled before it runs. -/
theorem awaitJoins_v12 : ¬ supAwaitJoinsV 12 :=
  awaitJoins_break 12 0 (.succeeded .unit) (by decide +kernel) (.inr ⟨by decide +kernel, by decide⟩)

/-! ## Statement 5: `supNoDeadlock` -/

/-- The child supervises a grandchild while `await = true` closes the supervisor: the
grandchild's `supervise` raises (the race of `supervise` and the finalizer), and the run ends. -/
theorem noDeadlock_sat :
    AllWF id (List.replicate 2 (.pure .unit)) [0, 1] (.pure .unit) u ∧
      (run id true false 0 (List.replicate 2 (.pure .unit)) [0, 1] (.pure .unit) u 900 []).halt
        = some (.done (.succeeded .unit)) ∧
      rejected (run id true false 0 (List.replicate 2 (.pure .unit)) [0, 1] (.pure .unit) u 900 []) 1 = 1 :=
  ⟨allWF_of id _ _ _ ok_pp, by decide +kernel, by decide +kernel⟩

/-- Variant 2 (`supervise` never returns): blocked. -/
theorem noDeadlock_v2 : ¬ supNoDeadlockV 2 := by
  intro h
  exact h u id false 0 1 [0] isOrder_id (by decide) (allWF_of id _ _ _ ok_p) 600 [] (by decide +kernel)

/-- Variant 6 (the factory never returns): blocked. -/
theorem noDeadlock_v6 : ¬ supNoDeadlockV 6 := by
  intro h
  exact h u id false 0 1 [0] isOrder_id (by decide) (allWF_of id _ _ _ ok_p) 600 [] (by decide +kernel)

/-! ## Statement 6: `supRemoved` -/

theorem removed_sat :
    AllWF id [p, nv] [0, 0] p u ∧
      (run id true false 0 [p, nv] [0, 0] p u 900 []).halt = some .blocked ∧
      status (run id true false 0 [p, nv] [0, 0] p u 900 []) 0 = 2 ∧
      (mapFibers (run id true false 0 [p, nv] [0, 0] p u 900 [])).length = 1 ∧
      (mapFibers (run id true false 0 [p, nv] [0, 0] p u 900 [])).all
        (terminated (run id true false 0 [p, nv] [0, 0] p u 900 []) · = false) = true :=
  ⟨allWF_of id _ _ _ ok_p_nv, by decide +kernel, by decide +kernel, by decide +kernel, by decide +kernel⟩

/-- Variant 10 (`remove` never removes): the finished child stays in the map. -/
theorem removed_v10 : ¬ supRemovedV 10 := by
  intro h
  have hb : (run id true false 0 [p, nv] [0, 0] p u 900 [] 10).halt = some .blocked := by decide +kernel
  have hx : ((mapFibers (run id true false 0 [p, nv] [0, 0] p u 900 [] 10)).filter
      (terminated (run id true false 0 [p, nv] [0, 0] p u 900 [] 10))).length = 1 := by decide +kernel
  have h' := h u id true 0 [p, nv] [0, 0] p isOrder_id (by decide) (allWF_of id _ _ _ ok_p_nv) 900 [] hb
  rw [List.filter_eq_nil_iff.mpr (fun x hx' => by simp [h' x hx'])] at hx
  simp at hx

/-! ## Statement 7: `supCancels` -/

theorem cancels_sat :
    AllWF id ([1].map Model.IO.sleep) [0] c u ∧
      (run id false false 0 ([1].map Model.IO.sleep) [0] c u 600 []).halt = some (.done (.succeeded .unit)) ∧
      status (run id false false 0 ([1].map Model.IO.sleep) [0] c u 600 []) 0 = 3 :=
  ⟨allWF_of id _ _ _ ok_c_sl, by decide +kernel, by decide +kernel⟩

/-- Variant 8 (`await = false` joins): the child finishes its sleep. -/
theorem cancels_v8 : ¬ supCancelsV 8 := by
  intro h
  have hd : (run id false false 0 ([1].map Model.IO.sleep) [0] p u 600 [] 8).halt
      = some (.done (.succeeded .unit)) := by decide +kernel
  have hs : status (run id false false 0 ([1].map Model.IO.sleep) [0] p u 600 [] 8) 0 = 2 := by decide +kernel
  exact h u id 0 [1] [0] p isOrder_id (by decide) (by simp) (.inl rfl) (allWF_of id _ _ _ ok_sl) 600 [] _ hd 0 hs

end CatsEffectInLean.Proofs.Phase7.SupervisorWitness
