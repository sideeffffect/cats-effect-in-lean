import CatsEffectInLean.Model.EnumP
import CatsEffectInLean.Model.Enum
import CatsEffectInLean.Model.IOInstance

/-!
# Preemption removes the iteration-count artifact (smoke tests, decision 36)

The law `uncancelablePollIsIdentity` (`F.uncancelable(poll => poll(fa)) <-> fa`) for

  `fa n = start(emit 9) >> emit 1 >> n flatMaps >> emit 2`

(a well-formed program: the child gets no handle, nobody names a forged id).

The left side runs two more run-loop iterations than the right side. With the replay `Eqv`
the auto-yield then falls at different program points, and the root-completion cut makes the
child's `emit 9` visible on one side only (`wiki/semantics/outcome-equivalence.md`).

* Small thresholds (`cancelationCheckThreshold = 2`, `autoYieldThreshold = 4`), so that the
  auto-yield comes often: the replay enumeration (picks 3, depth 4) differs for `n = 0, 1`
  (`replay_differs_*`), but the exact outcome sets with preemption are equal for `n = 0..3`
  (`eqvP_*`, all fuel values and all schedules).
* Default thresholds (512, 1024), `n = 509`: the replay enumeration (picks 3, depth 3, fuel
  1300; `#eval`, 2026-11-10) gives the trace `[1, 9, 2]` on the left side only. With one
  preemption after micro-step 514, the right side gives the same observation
  (`default_rhs_preempt`). So that difference is gone under `EqvP`.
-/

namespace CatsEffectInLean.Model.EnumPExamples

open CatsEffectInLean.Model

/-- User function `k` (even id `2 * k`). -/
def u (k : Nat) : Fn := .user (2 * k)

/-- `n` trailing `flatMap(_ => IO.pure(()))`. -/
def chain : Nat → IO → IO
  | 0, x => x
  | n + 1, x => chain n (.flatMap x (u 11))

/-- `fa n = start(emit 9) >> emit 1 >> n flatMaps >> emit 2`. -/
def faN (n : Nat) : IO :=
  .flatMap (chain n (.flatMap (.start (.delay (u 5))) (u 6))) (u 7)

/-- User code: 1 is `poll => poll(fa n)`; 3, 4, 5 are the thunks `emit 1`, `emit 2`, `emit 9`;
6, 7 are `_ => IO(emit 1)`, `_ => IO(emit 2)`; 11 is `_ => IO.pure(())`. -/
def envN (n : Nat) : UserEnv where
  call _ _ _ := { out := .throw { code := 0 } }
  callV id arg _ := match id, arg with
    | 2, .poll m s => { out := .prog (.unmaskRunLoop (faN n) m s) }
    | 6, _ => { effects := [.emit (.nat 1)], out := .ret .unit }
    | 8, _ => { effects := [.emit (.nat 2)], out := .ret .unit }
    | 10, _ => { effects := [.emit (.nat 9)], out := .ret .unit }
    | 12, _ => { out := .prog (.delay (u 3)) }
    | 14, _ => { out := .prog (.delay (u 4)) }
    | 22, _ => { out := .prog (.pure .unit) }
    | _, _ => { out := .throw { code := 0 } }

/-- `F.uncancelable(poll => poll(fa))`. -/
def lhs : IO := IOI.uncancelable (u 1)

theorem pollApply_envN (n : Nat) : IOI.Lam.pollApply (envN n) 2 (faN n) := fun _ _ _ => rfl

/-- Small run-loop thresholds: the auto-yield comes every 4 iterations. -/
def small : Config := { cancelationCheckThreshold := 2, autoYieldThreshold := 4 }

theorem replay_differs_0 :
    enumAgree small counterMaskModel (envN 0) 200 (picks 3) 4 lhs (faN 0) = false := by
  decide +kernel

theorem replay_differs_1 :
    enumAgree small counterMaskModel (envN 1) 200 (picks 3) 4 lhs (faN 1) = false := by
  decide +kernel

theorem eqvP_0 : EqvP small counterMaskModel (envN 0) lhs (faN 0) :=
  eqvP_of_checkEqvP _ _ _ (bound := 400) (by decide +kernel)

theorem eqvP_1 : EqvP small counterMaskModel (envN 1) lhs (faN 1) :=
  eqvP_of_checkEqvP _ _ _ (bound := 400) (by decide +kernel)

theorem eqvP_2 : EqvP small counterMaskModel (envN 2) lhs (faN 2) :=
  eqvP_of_checkEqvP _ _ _ (bound := 400) (by decide +kernel)

theorem eqvP_3 : EqvP small counterMaskModel (envN 3) lhs (faN 3) :=
  eqvP_of_checkEqvP _ _ _ (bound := 400) (by decide +kernel)

/-- The observation that the replay enumeration finds only on the left side at `n = 509`. -/
def obs192 : Obs :=
  { summary := .done (.succeeded .unit), out := [.nat 2, .nat 9, .nat 1], refs := [],
    reports := [] }

/-- With one preemption, the right side `fa 509` also gives `obs192`. -/
theorem default_rhs_preempt :
    runObsP {} counterMaskModel (envN 509) 3000
      (List.replicate 514 (.pick 0) ++ [.preempt]) (faN 509) = some obs192 := by
  decide +kernel

theorem default_rhs_outcomesP : outcomesP {} counterMaskModel (envN 509) (faN 509) obs192 :=
  ⟨_, _, default_rhs_preempt⟩

end CatsEffectInLean.Model.EnumPExamples
