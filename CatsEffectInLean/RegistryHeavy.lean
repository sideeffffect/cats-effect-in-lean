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
def heavyModules : Array Lean.Name := #[`CatsEffectInLean.Proofs.Phase6.RaceLaw]

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
      law row is modelled; race itself needs the open leak entries." }
]

end CatsEffectInLean
