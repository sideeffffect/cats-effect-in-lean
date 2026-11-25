import CatsEffectInLean.Proofs.Phase7.SupervisorWitness

/-!
# `Supervisor`: the restart-path wrong function (variant 11), kernel-checked

Review batch 16, N3: variant 11 of `Std/Supervisor.lean` (not Cats Effect code: the restart
ignores `canceled` and `done`, `SV:209`) broke `supNoLeak` only in the smoke test. Here it is a
kernel theorem. The restart path has large closure codes, so this module takes about 9 minutes
and 5 GB; it is not in the default build. CI builds it in the twin-check job
(`scripts/check_twin_checks.sh`, lakefile `TwinChecks`).

Input: `await = false`, `checkRestart = Some(_ => true)` (Dispatcher's `always`), one child that
never ends, body `IO.cede`, default schedule. Variant 11: the close cancels the child, its
finalizer restarts it, the new incarnation runs user code, and the wrapper's `cancel` raises the
"unexpected fiber" `AssertionError` (`SV:268-269`): the root is done (`Errored`) while the child
runs. Cats Effect v3.7.1 on the same input: the child is canceled once, the root `Succeeded(())`.
-/

namespace CatsEffectInLean.Proofs.Phase7.SupervisorRestartWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Props.Phase7.Supervisor
open CatsEffectInLean.Proofs.Phase7.SupervisorWitness

set_option maxHeartbeats 0 in
theorem noLeak_v11 : ¬ supNoLeakV 11 := by
  intro h
  have hd : (run id false true 0 [nv] [0] c u 300 [] 11).halt
      = some (.done (.errored CatsEffectInLean.Std.Supervisor.aeFiberErr)) := by decide +kernel
  have hs : status (run id false true 0 [nv] [0] c u 300 [] 11) 0 = 1 := by decide +kernel
  exact h u id false true 0 [nv] [0] c isOrder_id (by decide) (allWF_of id _ _ _ ok_c_nv) 300 []
    _ hd 0 hs

set_option maxHeartbeats 0 in
theorem noLeak_v0_restart :
    (run id false true 0 [nv] [0] c u 300 []).halt = some (.done (.succeeded .unit)) ∧
      status (run id false true 0 [nv] [0] c u 300 []) 0 = 3 ∧
      runs (run id false true 0 [nv] [0] c u 300 []) 0 = 1 :=
  ⟨by decide +kernel, by decide +kernel, by decide +kernel⟩

/-- Both checks (the twin-check job names this theorem). -/
theorem all_checks : ¬ supNoLeakV 11 ∧
    ((run id false true 0 [nv] [0] c u 300 []).halt = some (.done (.succeeded .unit)) ∧
      status (run id false true 0 [nv] [0] c u 300 []) 0 = 3 ∧
      runs (run id false true 0 [nv] [0] c u 300 []) 0 = 1) :=
  ⟨noLeak_v11, noLeak_v0_restart⟩

end CatsEffectInLean.Proofs.Phase7.SupervisorRestartWitness
