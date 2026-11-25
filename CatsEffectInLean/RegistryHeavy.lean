import CatsEffectInLean.Registry

/-!
# Registry of heavy proofs (decision 55)

Entries whose proofs take more than about 5 minutes to check. Their proof modules are in the
lean_lib `HeavyProofs` (`lakefile.lean`), not in the default target, so `lake build` and
`lake check` of the main CI job do not build them. Same `Entry` type as `Registry.lean`.

This module is light: it imports no heavy proof. So a theorem is named with a single backtick
and its full name (no compile-time check). The checks are in the audit:

* Main CI job (`lake exe audit`): every check of `Registry.lean`; for the entries here all
  checks that need no heavy module (id, rows, `prop`, status/theorem/bug consistency, ids
  unique across both registries, rows exist and name the entry back). A `modelled` row that
  only a heavy entry settles is **deferred**: the main job does not count it as checked.
* Heavy CI job (`scripts/check_heavy_proofs.sh`, `lake exe audit_heavy`): builds the heavy
  modules one Lean process at a time, then audits both registries in full (theorem exists,
  exact type, module, axioms) and runs the full inventory cross-check, deferred rows included.

So every check of the old single registry still runs on every push, in one of the two jobs.
-/

namespace CatsEffectInLean

/-- The modules with the heavy proofs (roots of lean_lib `HeavyProofs`). The heavy audit
imports them. -/
def heavyModules : Array Lean.Name := #[`CatsEffectInLean.Proofs.Phase6.RaceLaw,
  `CatsEffectInLean.Proofs.Phase7.DispatcherBattery]

/-- The heavy registry. -/
def registryHeavy : List Entry := [
  { id := "laws.GenSpawnLaws.uncancelableRaceNotInherited.IO"
    rows := ["laws.GenSpawnLaws.uncancelableRaceNotInherited", "core.IO.race", "kernel.GenSpawn.race"]
    prop := ``Props.Phase6.Race.uncancelableRaceNotInherited
    status := .proven
    thm := `CatsEffectInLean.Proofs.Phase6.RaceLaw.uncancelableRaceNotInherited_proven
    note := "Closed law (no input) under EqvP (all PChoice schedules, default Config, IOFiber \
      mask model). Proof by certificates (Proofs/Lemmas/CertP.lean, generator tools/CertGen): \
      left side exactly 4,441 states (closed), right side 45; every observation of both sides is \
      blocked with empty trace, refs and reports. Kernel check in 49 chunks \
      (Proofs/Phase6/RaceLawChunks*.lean), about 30 min; heavy registry (decision 55). Only the \
      law row is modelled; race itself needs the open leak entries." },
  { id := "std.Dispatcher.awaitDrains"
    rows := ["std.Dispatcher.parallel#2", "std.Dispatcher.sequential#2", "std.Dispatcher.unsafeToFutureCancelable", "std.Dispatcher.unsafeRunAndForget", "std.Dispatcher.Worker.run", "std.Dispatcher.Worker.apply", "std.Dispatcher.Executor.parallel", "std.Dispatcher.Executor.inplace"]
    prop := ``Props.Phase7.Dispatcher.dispAwaitDrains
    status := .refuted
    thm := `CatsEffectInLean.Proofs.Phase7.DispatcherBattery.dispAwaitDrains_refuted
    bug := some "bugs/CE-0091.yaml"
    note := "Phase 7, track P7D: await = true, pure effects submitted by the use body: a done root is Succeeded(()) and every effect ran to its end (Scaladoc DP:130-133, :160-163; issue #3506; the sequential drain test). Refuted (CE-0091): parallel(await = true), one effect submitted with unsafeToFutureCancelable, FIFO schedule (run R15, 216 micro-steps, kernel in chunks): the root is done, the effect never ran: the Worker finalizer offers the PoisonPill behind the registration, the executor Supervisor closes before the worker takes it, supervise raises IllegalStateException. Fixed twin 31 (the Worker finalizer waits until the worker took the pill): the effect runs (awaitDrains_twin31, R16). sequential meets it (awaitDrains_sat, R01). Wrong functions: 1, 3, 9, 11, 13, 16 (DispatcherBattery). Heavy (decision 55: the run needs about 2 min and 5.6 GB per chunk)." },
  { id := "std.Dispatcher.noLostSubmission"
    rows := ["std.Dispatcher.parallel#2", "std.Dispatcher.sequential#2", "std.Dispatcher.unsafeToFutureCancelable", "std.Dispatcher.unsafeToFuture", "std.Dispatcher.Worker.run", "std.Dispatcher.Worker.apply", "std.Dispatcher.Executor.parallel", "std.Dispatcher.UnsafeAsyncQueue.unsafeOffer", "std.Dispatcher.UnsafeAsyncQueue.take"]
    prop := ``Props.Phase7.Dispatcher.dispNoLostSubmission
    status := .refuted
    thm := `CatsEffectInLean.Proofs.Phase7.DispatcherBattery.dispNoLostSubmission_refuted
    bug := some "bugs/CE-0090.yaml"
    note := "Phase 7, track P7D: await = true, pure effects submitted by the use body and by a fiber the body starts; the root joins that fiber after use returned (review batch 16, B1). When the root is done, each submission threw IllegalStateException or its effect ran to its end (Scaladoc DP:130-133). Refuted (CE-0090): parallel(await = true), schedule sched 18 300 (run R32, 370 micro-steps): the body effect runs, the release waits for it, the concurrent submission passes the doneR check, returns (accepted, kernel fact ce0090_accepted_never_run), is queued behind the PoisonPill and never runs. Fixed twin 32 (doneR set before the pill, and the Worker finalizer waits for the pill): the conclusion holds on the same input and schedule (noLost_twin32, R33: the concurrent submission throws). Satisfiable (noLost_sat, R34). Heavy (decision 55)." }
]

end CatsEffectInLean
