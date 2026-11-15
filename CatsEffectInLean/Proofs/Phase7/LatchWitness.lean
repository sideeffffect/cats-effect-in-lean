import CatsEffectInLean.Props.Phase7.CountDownLatch
import CatsEffectInLean.Props.Phase7.CyclicBarrier

/-!
# `CountDownLatch` and `CyclicBarrier`: satisfiability witnesses and wrong-function tests

Phase 7, track L. Decision 53 (`wiki/methodology/agent-workflow.md`, "Satisfiable hypotheses"):
for each statement of `Props/Phase7/CountDownLatch.lean` and `Props/Phase7/CyclicBarrier.lean`,
one concrete input meets every hypothesis (`AllWF`, and `as.length < cap` for
`cbCancelRemoved`) and reaches the interesting case of the conclusion. Review rubric
("wrong-function test"): for each statement, a wrong variant of the mirror (`v ≠ 0`, not Cats
Effect code, `Std/CountDownLatch.lean`, `Std/CyclicBarrier.lean`) violates the conclusion on
well-formed inputs. All facts are evaluated by the kernel (`decide +kernel`).

The user programs are `IO.pure(())` (`p`) and a program that waits forever (`nv`: a new
`Deferred` read by the mirror's `await` selector, `CountDownLatch.State.initial(1)` then
`signal.get`; only public variant-0 mirror closures with no captured handle). There is no user
function: every even id throws (`u`).

| Statement | Witness (interesting case) | Wrong function (variant) |
|---|---|---|
| `cdlAwaitNotEarly` | `n = 2`, one awaiter, two releasers: the awaiter returns, `started = 2` | 1 (opens one `release` early): returns with `started = 1` |
| `cdlNoLostWakeup` | `n = 1`, a releaser that never ends: blocked, `started = 1`, the awaiter returned | 2 (never completes `signal`): blocked, `started = 1`, awaiter in `await` |
| `cdlReleaseTotal` | `n = 1`, two releasers (one after `Done`): done, `completed = started = 2` | 3 (raises after `Done`): done, `completed = 1`, `started = 2` |
| `cbNoEarlyTrip` | `cap = 2`, two awaiters: both return, `entered = 2` | 1 (trips at `cap - 1`): `passed = 1`, `entered = 2`, `cap = 3` |
| `cbExactGenerations` | `cap = 2`, three awaiters: blocked, `passed = 2`, `waiting = 1` | 4 (never completes `unblock`): blocked, `passed = 1` |
| `cbCancelNoHang` | `cap = 2`, A0 canceled while it waits, B0: blocked, `waiting = 1`, `canceledIn = 1` | 3 (no epoch check): A0 canceled, A1 trips before A0's cleanup runs, B0, B1 hang: `waiting = 2` |
| `cbCancelRemoved` | `cap = 2`, A0 canceled while it waits, B0, B1 trip: `passed = 2`, `entered = 3`, `canceledIn = 1` | 2 (no re-increment): B0 alone passes, `passed = 1`, `entered - canceledIn = 1` |

The `cbCancelNoHang` wrong-function witness is the race that the epoch check exists for: the
root cancels A0 while A0 is suspended in `unblock.get`; A0's finalizers run in a later task, and
A1 runs first and trips the barrier (A0 still counts). A0's cleanup then sees the new epoch.
Without the check it re-increments the next generation, which then needs `cap + 1` fibers. Cats
Effect v3.7.1 (variant 0) passes the same schedule (`cancelNoHang_v0_race`).
-/

namespace CatsEffectInLean.Proofs.Phase7.LatchWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec

/-- No user function: every user call throws. -/
def userR : UserResult := { out := .throw { code := 0 } }

def u : UserEnv := { call := fun _ _ _ => userR }

/-- `IO.pure(())`. -/
def p : IO := .pure .unit

/-- A program that waits forever: `Deferred` + the mirror's `await` selector on `Awaiting(1, d)`. -/
def nv : IO :=
  .flatMap (.map (.delay CatsEffectInLean.Std.CountDownLatch.CLam.newDeferred.fn)
    (CatsEffectInLean.Std.CountDownLatch.CLam.awaitingK 1).fn)
    CatsEffectInLean.Std.CountDownLatch.CLam.awaitSel.fn

/-! ## `CountDownLatch` -/

namespace CDL

open CatsEffectInLean.Props.Phase7.CountDownLatch

theorem callV_even (ws us : List IO) (id : Nat) (hid : id % 2 = 0) (a : Val) (v : View) :
    (env ws us u).callV id a v = userR := by
  have h1 : isLibId id = false := by simp [isLibId, hid]
  show CatsEffectInLean.Props.Phase7.CountDownLatch.dispatch ws us u id a v = _
  simp [CatsEffectInLean.Props.Phase7.CountDownLatch.dispatch, CatsEffectInLean.Std.CountDownLatch.CLam.ofId?,
    CatsEffectInLean.Props.Phase7.CountDownLatch.HLam.ofId?, h1, u]

/-- `WellFormed` for a closed program that calls no user code. -/
theorem wf (ws us : List IO) (q : IO)
    (hq : WF.progOK cdlLib (fun h => ([] : List Handle).contains h) q = true) :
    WellFormed cdlLib [] (env ws us u) q := by
  refine ⟨hq, fun id hid arg v => ⟨fun w _ => ?_, ?_⟩, ?_⟩
  · rw [callV_even ws us id hid, callV_even ws us id hid]
  · rw [callV_even ws us id hid]; simp [userR, WF.ResultOK, WF.EffectsOK, WF.OutOK]
  · refine WF.pollOpaque_of_const (env ws us u) (fun _ => userR) [] userR
      (fun id arg v hid => callV_even ws us id hid arg v) (by decide) (fun _ _ _ => rfl) ?_ (fun _ _ => rfl)
    intro σ _ k hk
    simp at hk

theorem p_ok : WF.progOK cdlLib (fun h => ([] : List Handle).contains h) p = true := by decide +kernel
theorem nv_ok : WF.progOK cdlLib (fun h => ([] : List Handle).contains h) nv = true := by decide +kernel

theorem allWF_p_pp : AllWF [p] [p, p] u := by
  intro q hq
  simp only [List.cons_append, List.nil_append, List.mem_cons, List.not_mem_nil, or_false] at hq
  rcases hq with rfl | rfl | rfl <;> exact wf _ _ _ p_ok

theorem allWF_p_p : AllWF [p] [p] u := by
  intro q hq
  simp only [List.cons_append, List.nil_append, List.mem_cons, List.not_mem_nil, or_false] at hq
  rcases hq with rfl | rfl <;> exact wf _ _ _ p_ok

theorem allWF_p_pnv : AllWF [p] [p, nv] u := by
  intro q hq
  simp only [List.cons_append, List.nil_append, List.mem_cons, List.not_mem_nil, or_false] at hq
  rcases hq with rfl | rfl | rfl
  · exact wf _ _ _ p_ok
  · exact wf _ _ _ p_ok
  · exact wf _ _ _ nv_ok

/-- `cdlAwaitNotEarly` is not vacuous: the awaiter returns (after two `release` calls). -/
theorem awaitNotEarly_sat :
    AllWF [p] [p, p] u ∧ status (run [p] [p, p] u 2 [] 61 []) 0 = 2 ∧
      started (run [p] [p, p] u 2 [] 61 []) = 2 :=
  ⟨allWF_p_pp, by decide +kernel, by decide +kernel⟩

/-- Wrong function (variant 1, opens one `release` early): the awaiter returns after one. -/
theorem awaitNotEarly_wrong :
    AllWF [p] [p] u ∧ status (run [p] [p] u 2 [] 48 [] 1) 0 = 2 ∧
      started (run [p] [p] u 2 [] 48 [] 1) = 1 :=
  ⟨allWF_p_p, by decide +kernel, by decide +kernel⟩

/-- `cdlNoLostWakeup` is not vacuous: blocked (a releaser never ends) with `started ≥ n`, and the
awaiter returned. -/
theorem noLostWakeup_sat :
    AllWF [p] [p, nv] u ∧ (run [p] [p, nv] u 1 [] 400 []).halt = some .blocked ∧
      started (run [p] [p, nv] u 1 [] 400 []) = 1 ∧ status (run [p] [p, nv] u 1 [] 400 []) 0 = 2 :=
  ⟨allWF_p_pnv, by decide +kernel, by decide +kernel, by decide +kernel⟩

/-- Wrong function (variant 2, never completes `signal`): the awaiter stays in `await`. -/
theorem noLostWakeup_wrong :
    AllWF [p] [p, nv] u ∧ (run [p] [p, nv] u 1 [] 400 [] 2).halt = some .blocked ∧
      started (run [p] [p, nv] u 1 [] 400 [] 2) = 1 ∧ status (run [p] [p, nv] u 1 [] 400 [] 2) 0 = 1 :=
  ⟨allWF_p_pnv, by decide +kernel, by decide +kernel, by decide +kernel⟩

/-- `cdlReleaseTotal` is not vacuous: a `release` after `Done` returns. -/
theorem releaseTotal_sat :
    AllWF [p] [p, p] u ∧ (run [p] [p, p] u 1 [] 400 []).halt = some (.done (.succeeded .unit)) ∧
      started (run [p] [p, p] u 1 [] 400 []) = 2 ∧ completed (run [p] [p, p] u 1 [] 400 []) = 2 :=
  ⟨allWF_p_pp, by decide +kernel, by decide +kernel, by decide +kernel⟩

/-- Wrong function (variant 3, raises after `Done`). -/
theorem releaseTotal_wrong :
    AllWF [p] [p, p] u ∧ (run [p] [p, p] u 1 [] 400 [] 3).halt = some (.done (.succeeded .unit)) ∧
      started (run [p] [p, p] u 1 [] 400 [] 3) = 2 ∧ completed (run [p] [p, p] u 1 [] 400 [] 3) = 1 :=
  ⟨allWF_p_pp, by decide +kernel, by decide +kernel, by decide +kernel⟩

end CDL

/-! ## `CyclicBarrier` -/

namespace CB

open CatsEffectInLean.Props.Phase7.CyclicBarrier

theorem callV_even (as bs : List IO) (id : Nat) (hid : id % 2 = 0) (a : Val) (v : View) :
    (env as bs u).callV id a v = userR := by
  have h1 : isLibId id = false := by simp [isLibId, hid]
  show CatsEffectInLean.Props.Phase7.CyclicBarrier.dispatch as bs u id a v = _
  simp [CatsEffectInLean.Props.Phase7.CyclicBarrier.dispatch, CatsEffectInLean.Std.CyclicBarrier.BLam.ofId?,
    CatsEffectInLean.Props.Phase7.CyclicBarrier.HLam.ofId?, h1, u]

theorem wf (as bs : List IO) (q : IO)
    (hq : WF.progOK cbLib (fun h => ([] : List Handle).contains h) q = true) :
    WellFormed cbLib [] (env as bs u) q := by
  refine ⟨hq, fun id hid arg v => ⟨fun w _ => ?_, ?_⟩, ?_⟩
  · rw [callV_even as bs id hid, callV_even as bs id hid]
  · rw [callV_even as bs id hid]; simp [userR, WF.ResultOK, WF.EffectsOK, WF.OutOK]
  · refine WF.pollOpaque_of_const (env as bs u) (fun _ => userR) [] userR
      (fun id arg v hid => callV_even as bs id hid arg v) (by decide) (fun _ _ _ => rfl) ?_ (fun _ _ => rfl)
    intro σ _ k hk
    simp at hk

theorem p_ok : WF.progOK cbLib (fun h => ([] : List Handle).contains h) p = true := by decide +kernel

/-- Every program in a list of `p`s is well-formed. -/
theorem allWF_ps (as bs : List IO) (ha : ∀ q ∈ as, q = p) (hb : ∀ q ∈ bs, q = p) : AllWF as bs u := by
  intro q hq
  rcases List.mem_append.mp hq with h | h
  · rw [ha q h]; exact wf _ _ _ p_ok
  · rw [hb q h]; exact wf _ _ _ p_ok

theorem allWF (as bs : List IO) (ha : as.all (· == p) = true) (hb : bs.all (· == p) = true) : AllWF as bs u :=
  allWF_ps as bs (fun q hq => by simpa using List.all_eq_true.mp ha q hq)
    (fun q hq => by simpa using List.all_eq_true.mp hb q hq)

/-- A preemption of the root after `k` micro-steps. -/
def cs1 (k : Nat) : List PChoice := List.replicate k (.pick 0) ++ [.preempt]

/-- The race schedule: preempt the root after 9 micro-steps, run A0 (it waits), then go on. -/
def race : List PChoice := List.replicate 9 (.pick 0) ++ [.preempt, .pick 0] ++ List.replicate 30 (.pick 0) ++ [.pick 0]

/-- `cbNoEarlyTrip` is not vacuous: a full generation is released. -/
theorem noEarlyTrip_sat :
    AllWF [p, p] [] u ∧ passed (run [p, p] [] u 2 [] 400 []) = 2 ∧ entered (run [p, p] [] u 2 [] 400 []) = 2 :=
  ⟨allWF _ _ (by decide) (by decide), by decide +kernel, by decide +kernel⟩

/-- Wrong function (variant 1, trips at `cap - 1`): with `cap = 3`, one fiber passes while only
two entered (`1 > 3 * (2 / 3) = 0`). -/
theorem noEarlyTrip_wrong :
    AllWF [p, p] [p] u ∧ passed (run [p, p] [p] u 3 [] 55 [] 1) = 1 ∧
      entered (run [p, p] [p] u 3 [] 55 [] 1) = 2 :=
  ⟨allWF _ _ (by decide) (by decide), by decide +kernel, by decide +kernel⟩

/-- `cbExactGenerations` is not vacuous: blocked after one full generation, one fiber waits. -/
theorem exactGenerations_sat :
    AllWF [p, p, p] [] u ∧ (run [p, p, p] [] u 2 [] 400 []).halt = some .blocked ∧
      passed (run [p, p, p] [] u 2 [] 400 []) = 2 ∧ waiting (run [p, p, p] [] u 2 [] 400 []) = 1 :=
  ⟨allWF _ _ (by decide) (by decide), by decide +kernel, by decide +kernel, by decide +kernel⟩

/-- Wrong function (variant 4, never completes `unblock`): only the tripper returns. -/
theorem exactGenerations_wrong :
    AllWF [p, p] [] u ∧ (run [p, p] [] u 2 [] 400 [] 4).halt = some .blocked ∧
      passed (run [p, p] [] u 2 [] 400 [] 4) = 1 :=
  ⟨allWF _ _ (by decide) (by decide), by decide +kernel, by decide +kernel⟩

/-- `cbCancelNoHang` is not vacuous: A0 is canceled while it waits; blocked with B0 waiting. -/
theorem cancelNoHang_sat :
    AllWF [p] [p] u ∧ (run [p] [p] u 2 [0] 600 (cs1 9)).halt = some .blocked ∧
      canceledIn (run [p] [p] u 2 [0] 600 (cs1 9)) = 1 ∧ waiting (run [p] [p] u 2 [0] 600 (cs1 9)) = 1 :=
  ⟨allWF _ _ (by decide) (by decide), by decide +kernel, by decide +kernel, by decide +kernel⟩

/-- Wrong function (variant 3, no epoch check) on the race schedule: two fibers hang with
`cap = 2`. -/
theorem cancelNoHang_wrong :
    AllWF [p, p] [p, p] u ∧ (run [p, p] [p, p] u 2 [0] 800 race 3).halt = some .blocked ∧
      waiting (run [p, p] [p, p] u 2 [0] 800 race 3) = 2 :=
  ⟨allWF _ _ (by decide) (by decide), by decide +kernel, by decide +kernel⟩

/-- Cats Effect v3.7.1 on the same race schedule: A0 is canceled, the rest complete. -/
theorem cancelNoHang_v0_race :
    (run [p, p] [p, p] u 2 [0] 800 race).halt = some (.done (.succeeded .unit)) ∧
      canceledIn (run [p, p] [p, p] u 2 [0] 800 race) = 1 ∧ passed (run [p, p] [p, p] u 2 [0] 800 race) = 3 :=
  ⟨by decide +kernel, by decide +kernel, by decide +kernel⟩

/-- `cbCancelRemoved` is not vacuous: `as.length < cap`, A0 is canceled while it waits, and the
next two awaiters trip the barrier. -/
theorem cancelRemoved_sat :
    AllWF [p] [p, p] u ∧ [p].length < 2 ∧ passed (run [p] [p, p] u 2 [0] 600 (cs1 9)) = 2 ∧
      entered (run [p] [p, p] u 2 [0] 600 (cs1 9)) = 3 ∧ canceledIn (run [p] [p, p] u 2 [0] 600 (cs1 9)) = 1 :=
  ⟨allWF _ _ (by decide) (by decide), by decide, by decide +kernel, by decide +kernel, by decide +kernel⟩

/-- Wrong function (variant 2, the cleanup does not re-increment): B0 alone trips the barrier. -/
theorem cancelRemoved_wrong :
    AllWF [p] [p] u ∧ passed (run [p] [p] u 2 [0] 600 (cs1 9) 2) = 1 ∧
      entered (run [p] [p] u 2 [0] 600 (cs1 9) 2) = 2 ∧ canceledIn (run [p] [p] u 2 [0] 600 (cs1 9) 2) = 1 :=
  ⟨allWF _ _ (by decide) (by decide), by decide +kernel, by decide +kernel, by decide +kernel⟩

end CB

/-! ## The wrong functions violate the statements (the statements with the variant)

The registered statements use variant 0. The same quantified statements with a wrong variant
are false: each `*_wrong` fact above is a counterexample. Two examples written out: -/

open CatsEffectInLean.Props.Phase7.CountDownLatch in
/-- `cdlAwaitNotEarly` with variant 1 instead of 0 is false. -/
theorem cdlAwaitNotEarly_v1_false :
    ¬ ∀ (u : UserEnv) (n : Nat) (ws us : List IO) (cancels : List Nat), AllWF ws us u →
      ∀ (fuel : Nat) (cs : List PChoice) (j : Nat),
        status (run ws us u n cancels fuel cs 1) j = 2 → n ≤ started (run ws us u n cancels fuel cs 1) := by
  intro h
  have := h u 2 [p] [p] [] CDL.awaitNotEarly_wrong.1 48 [] 0 CDL.awaitNotEarly_wrong.2.1
  rw [CDL.awaitNotEarly_wrong.2.2] at this
  omega

open CatsEffectInLean.Props.Phase7.CyclicBarrier in
/-- `cbCancelNoHang` with variant 3 (no epoch check) instead of 0 is false. -/
theorem cbCancelNoHang_v3_false :
    ¬ ∀ (u : UserEnv) (cap : Nat) (as bs : List IO) (cancels : List Nat), AllWF as bs u →
      ∀ (fuel : Nat) (cs : List PChoice),
        (run as bs u cap cancels fuel cs 3).halt = some .blocked → waiting (run as bs u cap cancels fuel cs 3) < cap := by
  intro h
  have := h u 2 [p, p] [p, p] [0] CB.cancelNoHang_wrong.1 800 CB.race CB.cancelNoHang_wrong.2.1
  rw [CB.cancelNoHang_wrong.2.2] at this
  omega

end CatsEffectInLean.Proofs.Phase7.LatchWitness
